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
}

pub async fn parse_play_url(
    State(state): State<AppState>,
    Query(query): Query<ParsePlayUrlQuery>,
) -> ApiResult<PlayResult> {
    info!("解析播放链接API调用");

    let result = state.play_parser.parse_play_url(&query.play_url)?;

    Ok(Json(ApiResponse::success(result)))
}
