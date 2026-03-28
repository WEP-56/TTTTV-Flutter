use crate::core::AppState;
use crate::models::VodItem;
use crate::utils::response::{ApiResponse, ApiResult};
use axum::{
    Json,
    extract::{Query, State},
};
use serde::Deserialize;
use tracing::info;

#[derive(Deserialize)]
pub struct SearchQuery {
    pub kw: String,
    pub bypass: Option<bool>,
}

#[derive(serde::Serialize)]
pub struct SearchApiResult {
    pub items: Vec<VodItem>,
    pub filtered_count: usize,
}

pub async fn search(
    State(state): State<AppState>,
    Query(query): Query<SearchQuery>,
) -> ApiResult<SearchApiResult> {
    info!("搜索API调用: {}", query.kw);

    let result = state
        .search_service
        .search(&query.kw, query.bypass.unwrap_or(false))
        .await?;

    Ok(Json(ApiResponse::success(SearchApiResult {
        items: result.items,
        filtered_count: result.filtered_count,
    })))
}

#[derive(Deserialize)]
pub struct DetailQuery {
    pub source_key: String,
    pub vod_id: String,
}

pub async fn get_detail(
    State(state): State<AppState>,
    Query(query): Query<DetailQuery>,
) -> ApiResult<VodItem> {
    info!("获取详情API调用: {} - {}", query.source_key, query.vod_id);

    let item = state
        .search_service
        .get_detail(&query.source_key, &query.vod_id)
        .await?;

    Ok(Json(ApiResponse::success(item)))
}
