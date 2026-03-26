use axum::{
    extract::{Query, State},
    routing::{delete, get, post},
    Json, Router,
};
use chrono::Utc;
use serde::{Deserialize, Serialize};

use crate::core::app_state::AppState;
use crate::core::storage::LiveHistoryItem;
use crate::utils::response::{ApiResponse, ApiResult};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AddLiveHistoryRequest {
    pub platform: String,
    pub room_id: String,
    pub title: String,
    pub cover: Option<String>,
    pub user_name: Option<String>,
    pub user_avatar: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DeleteLiveHistoryRequest {
    pub platform: String,
    pub room_id: String,
}

pub fn router() -> Router<AppState> {
    Router::new()
        .route("/", get(get_live_history))
        .route("/", post(add_live_history))
        .route("/", delete(delete_live_history))
        .route("/clear", delete(clear_live_history))
}

pub async fn get_live_history(State(state): State<AppState>) -> ApiResult<Vec<LiveHistoryItem>> {
    let storage = state.storage.lock().unwrap();
    let items = storage.get_live_history().to_vec();
    Ok(Json(ApiResponse::success(items)))
}

pub async fn add_live_history(
    State(state): State<AppState>,
    Json(request): Json<AddLiveHistoryRequest>,
) -> ApiResult<()> {
    let mut storage = state.storage.lock().unwrap();
    let item = LiveHistoryItem {
        platform: request.platform,
        room_id: request.room_id,
        title: request.title,
        cover: request.cover,
        user_name: request.user_name,
        user_avatar: request.user_avatar,
        last_watch_time: Utc::now().timestamp(),
    };
    storage.add_live_history(item)?;
    Ok(Json(ApiResponse::success(())))
}

pub async fn delete_live_history(
    State(state): State<AppState>,
    Query(query): Query<DeleteLiveHistoryRequest>,
) -> ApiResult<()> {
    let mut storage = state.storage.lock().unwrap();
    storage.remove_live_history(&query.platform, &query.room_id)?;
    Ok(Json(ApiResponse::success(())))
}

pub async fn clear_live_history(State(state): State<AppState>) -> ApiResult<()> {
    let mut storage = state.storage.lock().unwrap();
    storage.clear_live_history()?;
    Ok(Json(ApiResponse::success(())))
}

