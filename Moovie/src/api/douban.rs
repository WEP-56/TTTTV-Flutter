use axum::{
    Json,
    extract::{Query, State},
    http::StatusCode,
    response::IntoResponse,
};
use reqwest::header::{ACCEPT, ACCEPT_LANGUAGE, HeaderMap, HeaderValue, REFERER, USER_AGENT};
use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::collections::HashMap;

use crate::core::AppState;
use crate::utils::response::ApiResponse;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DoubanSubject {
    pub id: Option<String>,
    pub title: String,
    pub cover: Option<String>,
    pub cover_url: Option<String>,
    pub rate: Option<String>,
    pub year: Option<String>,
    pub url: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DoubanSearchResponse {
    pub subjects: Vec<DoubanSubject>,
    pub total: Option<i32>,
}

#[derive(Debug, Clone, Deserialize)]
pub struct DoubanNewSearchResponse {
    pub data: Option<Vec<DoubanSubject>>,
    pub total: Option<i32>,
}

#[derive(Debug, Clone, Deserialize)]
pub struct DoubanQuery {
    #[serde(rename = "type")]
    pub media_type: Option<String>,
    pub tag: Option<String>,
    pub sort: Option<String>,
    pub page_limit: Option<u32>,
    pub page_start: Option<u32>,
    pub start: Option<String>,
    pub range: Option<String>,
    pub genres: Option<String>,
    pub countries: Option<String>,
    pub tags: Option<String>,
}

const USER_AGENTS: &[&str] = &[
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/121.0.0.0 Safari/537.36",
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15",
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:109.0) Gecko/20100101 Firefox/121.0",
];

fn get_random_user_agent() -> &'static str {
    use rand::Rng;
    let mut rng = rand::thread_rng();
    let index = rng.gen_range(0..USER_AGENTS.len());
    USER_AGENTS[index]
}

fn build_headers() -> HeaderMap {
    let mut headers = HeaderMap::new();

    if let Ok(ua) = HeaderValue::from_str(get_random_user_agent()) {
        headers.insert(USER_AGENT, ua);
    }
    headers.insert(
        REFERER,
        HeaderValue::from_static("https://movie.douban.com/"),
    );
    headers.insert(
        ACCEPT,
        HeaderValue::from_static("application/json, text/plain, */*"),
    );
    headers.insert(
        ACCEPT_LANGUAGE,
        HeaderValue::from_static("zh-CN,zh;q=0.9,en;q=0.8"),
    );
    headers.insert(
        "X-Requested-With",
        HeaderValue::from_static("XMLHttpRequest"),
    );

    headers
}

pub async fn fetch_douban_search_subjects(
    client: &reqwest::Client,
    query: &DoubanQuery,
) -> Result<DoubanSearchResponse, String> {
    let media_type = query.media_type.as_deref().unwrap_or("movie");
    let tag = query.tag.as_deref().unwrap_or("热门");
    let sort = query.sort.as_deref().unwrap_or("recommend");
    let page_limit = query.page_limit.unwrap_or(20);
    let page_start = query.page_start.unwrap_or(0);

    let url = format!(
        "https://movie.douban.com/j/search_subjects?type={}&tag={}&sort={}&page_limit={}&page_start={}",
        urlencoding::encode(media_type),
        urlencoding::encode(tag),
        urlencoding::encode(sort),
        page_limit,
        page_start
    );

    let response = client
        .get(&url)
        .headers(build_headers())
        .timeout(std::time::Duration::from_secs(30))
        .send()
        .await
        .map_err(|e| format!("请求失败: {}", e))?;

    let status = response.status();
    if !status.is_success() {
        return Err(format!("HTTP 错误: {}", status));
    }

    let text = response
        .text()
        .await
        .map_err(|e| format!("读取响应失败: {}", e))?;

    if text.contains("检测到有异常请求") {
        return Err("豆瓣限流".to_string());
    }

    let data: DoubanSearchResponse =
        serde_json::from_str(&text).map_err(|e| format!("解析JSON失败: {}, 响应: {}", e, text))?;

    Ok(data)
}

pub async fn fetch_douban_new_search(
    client: &reqwest::Client,
    query: &DoubanQuery,
) -> Result<DoubanSearchResponse, String> {
    let mut params = HashMap::new();

    if let Some(sort) = &query.sort {
        params.insert("sort", sort.clone());
    }
    if let Some(range) = &query.range {
        params.insert("range", range.clone());
    }
    if let Some(tags) = &query.tags {
        params.insert("tags", tags.clone());
    }
    if let Some(start) = &query.start {
        params.insert("start", start.clone());
    }
    if let Some(genres) = &query.genres {
        params.insert("genres", genres.clone());
    }
    if let Some(countries) = &query.countries {
        params.insert("countries", countries.clone());
    }

    let url =
        reqwest::Url::parse_with_params("https://movie.douban.com/j/new_search_subjects", &params)
            .map_err(|e| format!("构建URL失败: {}", e))?;

    let response = client
        .get(url)
        .headers(build_headers())
        .timeout(std::time::Duration::from_secs(30))
        .send()
        .await
        .map_err(|e| format!("请求失败: {}", e))?;

    let status = response.status();
    if !status.is_success() {
        return Err(format!("HTTP 错误: {}", status));
    }

    let text = response
        .text()
        .await
        .map_err(|e| format!("读取响应失败: {}", e))?;

    if text.contains("检测到有异常请求") {
        return Err("豆瓣限流".to_string());
    }

    let new_data: DoubanNewSearchResponse =
        serde_json::from_str(&text).map_err(|e| format!("解析JSON失败: {}, 响应: {}", e, text))?;

    Ok(DoubanSearchResponse {
        subjects: new_data.data.unwrap_or_default(),
        total: new_data.total,
    })
}

pub async fn douban_search(
    State(state): State<AppState>,
    Query(query): Query<DoubanQuery>,
) -> impl IntoResponse {
    let client = state.client.clone();

    let use_new_api = query.tags.is_some() || query.genres.is_some() || query.countries.is_some();

    let result = if use_new_api {
        fetch_douban_new_search(&client, &query).await
    } else {
        fetch_douban_search_subjects(&client, &query).await
    };

    match result {
        Ok(data) => (
            StatusCode::OK,
            Json(ApiResponse::success_with_message(data, "获取成功")),
        ),
        Err(e) => (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(ApiResponse::<DoubanSearchResponse>::error(&e)),
        ),
    }
}

pub async fn douban_chart_top_list(
    State(state): State<AppState>,
    Query(params): Query<HashMap<String, String>>,
) -> impl IntoResponse {
    let client = state.client.clone();

    let type_param = params.get("type").cloned().unwrap_or("11".to_string());
    let interval_id = params
        .get("interval_id")
        .cloned()
        .unwrap_or("100:90".to_string());
    let action = params.get("action").cloned().unwrap_or_default();
    let start = params.get("start").cloned().unwrap_or("0".to_string());
    let limit = params.get("limit").cloned().unwrap_or("20".to_string());

    let url = match reqwest::Url::parse_with_params(
        "https://movie.douban.com/j/chart/top_list",
        &[
            ("type", type_param),
            ("interval_id", interval_id),
            ("action", action),
            ("start", start),
            ("limit", limit),
        ],
    ) {
        Ok(u) => u,
        Err(e) => {
            return (
                StatusCode::BAD_REQUEST,
                Json(ApiResponse::<DoubanSearchResponse>::error(&format!(
                    "构建URL失败: {}",
                    e
                ))),
            );
        }
    };

    let response = match client
        .get(url)
        .headers(build_headers())
        .timeout(std::time::Duration::from_secs(30))
        .send()
        .await
    {
        Ok(r) => r,
        Err(e) => {
            return (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(ApiResponse::<DoubanSearchResponse>::error(&format!(
                    "请求失败: {}",
                    e
                ))),
            );
        }
    };

    let status = response.status();
    if !status.is_success() {
        return (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(ApiResponse::<DoubanSearchResponse>::error(&format!(
                "HTTP 错误: {}",
                status
            ))),
        );
    }

    let text = match response.text().await {
        Ok(t) => t,
        Err(e) => {
            return (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(ApiResponse::<DoubanSearchResponse>::error(&format!(
                    "读取响应失败: {}",
                    e
                ))),
            );
        }
    };

    if text.contains("检测到有异常请求") {
        return (
            StatusCode::TOO_MANY_REQUESTS,
            Json(ApiResponse::<DoubanSearchResponse>::error("豆瓣限流")),
        );
    }

    let subjects: Vec<DoubanSubject> = match serde_json::from_str(&text) {
        Ok(s) => s,
        Err(e) => {
            return (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(ApiResponse::<DoubanSearchResponse>::error(&format!(
                    "解析JSON失败: {}",
                    e
                ))),
            );
        }
    };

    (
        StatusCode::OK,
        Json(ApiResponse::success_with_message(
            DoubanSearchResponse {
                subjects,
                total: None,
            },
            "获取成功",
        )),
    )
}
