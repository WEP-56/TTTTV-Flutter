use crate::core::AppState;
use crate::services::PlayResult;
use crate::utils::response::{ApiResponse, ApiResult};
use axum::{
    Json,
    extract::{Query, State},
};
use serde::Deserialize;
use tracing::info;

#[derive(Deserialize)]
pub struct ParsePlayUrlQuery {
    pub play_url: String,
    /// 数据源的 detail 域名，用于 M3U8 防盗链代理的 Referer，可选
    pub referer: Option<String>,
}

pub async fn parse_play_url(
    State(state): State<AppState>,
    Query(query): Query<ParsePlayUrlQuery>,
) -> ApiResult<PlayResult> {
    info!("解析播放链接API调用");

    let referer = query.referer.as_deref().unwrap_or("");
    let result = state.play_parser.parse_play_url(&query.play_url, referer);

    Ok(Json(ApiResponse::success(result)))
}
