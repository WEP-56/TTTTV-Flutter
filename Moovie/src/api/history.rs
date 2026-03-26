use axum::{
    extract::State,
    routing::{get, post, delete},
    Json, Router,
};
use axum::extract::Query;
use chrono::Utc;
use serde::{Deserialize, Serialize};

use crate::core::app_state::AppState;
use crate::core::storage::WatchHistoryItem;
use crate::utils::response::{ApiResponse, ApiResult};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AddWatchHistoryRequest {
    pub vod_id: String,
    pub source_key: String,
    pub vod_name: String,
    pub vod_pic: Option<String>,
    pub progress: f64,
    pub episode: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DeleteWatchHistoryRequest {
    pub vod_id: String,
    pub source_key: String,
}

pub fn router() -> Router<AppState> {
    Router::new()
        .route("/", get(get_watch_history))
        .route("/", post(add_watch_history))
        .route("/", delete(delete_watch_history))
        .route("/clear", delete(clear_watch_history))
}

pub async fn get_watch_history(
    State(state): State<AppState>,
) -> ApiResult<Vec<WatchHistoryItem>> {
    let storage = state.storage.lock().unwrap();
    let history = storage.get_watch_history().to_vec();
    Ok(Json(ApiResponse::success(history)))
}

pub async fn add_watch_history(
    State(state): State<AppState>,
    Json(request): Json<AddWatchHistoryRequest>,
) -> ApiResult<()> {
    let mut storage = state.storage.lock().unwrap();
    
    let item = WatchHistoryItem {
        vod_id: request.vod_id,
        source_key: request.source_key,
        vod_name: request.vod_name,
        vod_pic: request.vod_pic,
        last_play_time: Utc::now().timestamp(),
        progress: request.progress,
        episode: request.episode,
    };
    
    storage.add_watch_history(item)?;
    
    Ok(Json(ApiResponse::success(())))
}

pub async fn delete_watch_history(
    State(state): State<AppState>,
    Query(query): Query<DeleteWatchHistoryRequest>,
) -> ApiResult<()> {
    let mut storage = state.storage.lock().unwrap();
    storage.remove_watch_history(&query.vod_id, &query.source_key)?;
    Ok(Json(ApiResponse::success(())))
}

pub async fn clear_watch_history(
    State(state): State<AppState>,
) -> ApiResult<()> {
    let mut storage = state.storage.lock().unwrap();
    storage.clear_watch_history()?;
    Ok(Json(ApiResponse::success(())))
}
