use axum::{
    extract::{Query, State},
    routing::{get, post},
    Json, Router,
};
use qrcode::QrCode;
use qrcode::render::svg;
use serde::{Deserialize, Serialize};
use serde_json::Value;

use crate::core::app_state::AppState;
use crate::utils::error::{MoovieError, Result};
use crate::utils::response::{ApiResponse, ApiResult};

pub fn router() -> Router<AppState> {
    Router::new()
        .route("/bilibili/status", get(bilibili_status))
        .route("/bilibili/logout", post(bilibili_logout))
        .route("/bilibili/qrcode", get(bilibili_qrcode))
        .route("/bilibili/qrcode/poll", get(bilibili_qrcode_poll))
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BilibiliStatusResponse {
    pub logged_in: bool,
}

pub async fn bilibili_status(State(state): State<AppState>) -> ApiResult<BilibiliStatusResponse> {
    let cookie = state
        .storage
        .lock()
        .unwrap()
        .get_live_cookie("bilibili")
        .unwrap_or_default();
    Ok(Json(ApiResponse::success(BilibiliStatusResponse {
        logged_in: !cookie.trim().is_empty(),
    })))
}

pub async fn bilibili_logout(State(state): State<AppState>) -> ApiResult<()> {
    let mut storage = state.storage.lock().unwrap();
    storage.set_live_cookie("bilibili", "".to_string())?;
    Ok(Json(ApiResponse::success(())))
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BilibiliQrCodeResponse {
    pub qrcode_key: String,
    pub url: String,
    pub svg: String,
}

pub async fn bilibili_qrcode(State(state): State<AppState>) -> ApiResult<BilibiliQrCodeResponse> {
    let resp = state
        .client
        .get("https://passport.bilibili.com/x/passport-login/web/qrcode/generate")
        .header(
            "user-agent",
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36",
        )
        .header("referer", "https://www.bilibili.com/")
        .send()
        .await?
        .json::<Value>()
        .await?;

    if resp["code"].as_i64().unwrap_or(-1) != 0 {
        return Err(MoovieError::ConfigError(
            resp["message"].as_str().unwrap_or("获取二维码失败").to_string(),
        ));
    }

    let qrcode_key = resp["data"]["qrcode_key"]
        .as_str()
        .unwrap_or("")
        .to_string();
    let url = resp["data"]["url"].as_str().unwrap_or("").to_string();

    if qrcode_key.is_empty() || url.is_empty() {
        return Err(MoovieError::ConfigError("获取二维码失败".to_string()));
    }

    let code = QrCode::new(url.as_bytes())
        .map_err(|e| MoovieError::ConfigError(format!("二维码生成失败: {}", e)))?;
    let svg = code
        .render::<svg::Color>()
        .min_dimensions(240, 240)
        .build();

    Ok(Json(ApiResponse::success(BilibiliQrCodeResponse {
        qrcode_key,
        url,
        svg,
    })))
}

#[derive(Debug, Clone, Deserialize)]
pub struct BilibiliQrPollQuery {
    pub qrcode_key: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BilibiliQrPollResponse {
    pub code: i64,
    pub status: String,
    pub message: String,
}

pub async fn bilibili_qrcode_poll(
    State(state): State<AppState>,
    Query(query): Query<BilibiliQrPollQuery>,
) -> ApiResult<BilibiliQrPollResponse> {
    if query.qrcode_key.trim().is_empty() {
        return Err(MoovieError::InvalidParameter(
            "qrcode_key 不能为空".to_string(),
        ));
    }

    let resp = state
        .client
        .get("https://passport.bilibili.com/x/passport-login/web/qrcode/poll")
        .query(&[("qrcode_key", &query.qrcode_key)])
        .header(
            "user-agent",
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36",
        )
        .header("referer", "https://www.bilibili.com/")
        .send()
        .await?;

    let headers = resp.headers().clone();
    let body = resp.json::<Value>().await?;

    if body["code"].as_i64().unwrap_or(-1) != 0 {
        return Err(MoovieError::ConfigError(
            body["message"].as_str().unwrap_or("二维码状态查询失败").to_string(),
        ));
    }

    let data = &body["data"];
    let code = data["code"].as_i64().unwrap_or(-1);
    let message = data["message"].as_str().unwrap_or("").to_string();

    let (status, should_store_cookie) = match code {
        0 => ("success", true),
        86101 => ("unscanned", false),
        86090 => ("scanned", false),
        86038 => ("expired", false),
        _ => ("failed", false),
    };

    if should_store_cookie {
        let mut cookies: Vec<String> = Vec::new();
        for value in headers.get_all(axum::http::header::SET_COOKIE).iter() {
            if let Ok(s) = value.to_str() {
                if let Some(pair) = s.split(';').next() {
                    let pair = pair.trim();
                    if !pair.is_empty() {
                        cookies.push(pair.to_string());
                    }
                }
            }
        }
        if !cookies.is_empty() {
            let cookie_str = cookies.join(";");
            let mut storage = state.storage.lock().unwrap();
            storage.set_live_cookie("bilibili", cookie_str)?;
        } else {
            return Err(MoovieError::ConfigError(
                "登录成功但未获取到 Cookie".to_string(),
            ));
        }
    }

    Ok(Json(ApiResponse::success(BilibiliQrPollResponse {
        code,
        status: status.to_string(),
        message,
    })))
}

