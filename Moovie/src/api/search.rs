use crate::core::AppState;
use crate::models::VodItem;
use crate::utils::response::{ApiResponse, ApiResult};
use axum::{
    Json,
    extract::{Query, State},
    response::{
        IntoResponse, Response,
        sse::{Event, KeepAlive, Sse},
    },
};
use futures::StreamExt;
use serde::Deserialize;
use tokio_stream::wrappers::ReceiverStream;
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

/// 从 AppState 构建 site_key → response_time_ms 的映射，供动态超时使用
fn build_speed_map(state: &AppState) -> std::collections::HashMap<String, Option<i64>> {
    let storage = state.storage.lock().unwrap();
    let site_states = storage.get_all_site_states();
    site_states
        .into_iter()
        .map(|(key, state)| (key.clone(), state.response_time_ms))
        .collect()
}

/// 普通搜索：等所有站点完成后一次性返回（兼容旧接口）
pub async fn search(
    State(state): State<AppState>,
    Query(query): Query<SearchQuery>,
) -> ApiResult<SearchApiResult> {
    info!("搜索API调用: {}", query.kw);

    let speed_map = build_speed_map(&state);
    let result = state
        .search_service
        .search(&query.kw, query.bypass.unwrap_or(false), speed_map)
        .await?;

    Ok(Json(ApiResponse::success(SearchApiResult {
        items: result.items,
        filtered_count: result.filtered_count,
    })))
}

/// SSE 流式搜索：每个站点完成立即推送，前端可逐步展示结果
pub async fn search_stream(
    State(state): State<AppState>,
    Query(query): Query<SearchQuery>,
) -> Response {
    info!("流式搜索API调用: {}", query.kw);

    let speed_map = build_speed_map(&state);
    let bypass = query.bypass.unwrap_or(false);
    let rx = state.search_service.search_stream(&query.kw, bypass, speed_map);
    let receiver_stream = ReceiverStream::new(rx);

    let event_stream = receiver_stream.map(|event| {
        let data = serde_json::to_string(&event).unwrap_or_default();
        Ok::<Event, std::convert::Infallible>(Event::default().data(data))
    });

    Sse::new(event_stream)
        .keep_alive(KeepAlive::default())
        .into_response()
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
