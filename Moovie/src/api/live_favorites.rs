use axum::{
    Json, Router,
    extract::{Query, State},
    routing::{delete, get, post},
};
use chrono::Utc;
use serde::{Deserialize, Serialize};

use crate::core::app_state::AppState;
use crate::core::storage::LiveFavoriteItem;
use crate::utils::response::{ApiResponse, ApiResult};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AddLiveFavoriteRequest {
    pub platform: String,
    pub room_id: String,
    pub title: String,
    pub cover: Option<String>,
    pub user_name: Option<String>,
    pub user_avatar: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DeleteLiveFavoriteRequest {
    pub platform: String,
    pub room_id: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CheckLiveFavoriteRequest {
    pub platform: String,
    pub room_id: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CheckLiveFavoriteResponse {
    pub is_favorited: bool,
}

pub fn router() -> Router<AppState> {
    Router::new()
        .route("/", get(get_live_favorites))
        .route("/", post(add_live_favorite))
        .route("/", delete(delete_live_favorite))
        .route("/check", get(check_live_favorite))
        .route("/clear", delete(clear_live_favorites))
}

pub async fn get_live_favorites(State(state): State<AppState>) -> ApiResult<Vec<LiveFavoriteItem>> {
    let storage = state.storage.lock().unwrap();
    let items = storage.get_live_favorites().to_vec();
    Ok(Json(ApiResponse::success(items)))
}

pub async fn add_live_favorite(
    State(state): State<AppState>,
    Json(request): Json<AddLiveFavoriteRequest>,
) -> ApiResult<()> {
    let mut storage = state.storage.lock().unwrap();
    let item = LiveFavoriteItem {
        platform: request.platform,
        room_id: request.room_id,
        title: request.title,
        cover: request.cover,
        user_name: request.user_name,
        user_avatar: request.user_avatar,
        created_time: Utc::now().timestamp(),
    };
    storage.add_live_favorite(item)?;
    Ok(Json(ApiResponse::success(())))
}

pub async fn delete_live_favorite(
    State(state): State<AppState>,
    Query(query): Query<DeleteLiveFavoriteRequest>,
) -> ApiResult<()> {
    let mut storage = state.storage.lock().unwrap();
    storage.remove_live_favorite(&query.platform, &query.room_id)?;
    Ok(Json(ApiResponse::success(())))
}

pub async fn check_live_favorite(
    State(state): State<AppState>,
    Query(query): Query<CheckLiveFavoriteRequest>,
) -> ApiResult<CheckLiveFavoriteResponse> {
    let storage = state.storage.lock().unwrap();
    let is_favorited = storage.is_live_favorited(&query.platform, &query.room_id);
    Ok(Json(ApiResponse::success(CheckLiveFavoriteResponse {
        is_favorited,
    })))
}

pub async fn clear_live_favorites(State(state): State<AppState>) -> ApiResult<()> {
    let mut storage = state.storage.lock().unwrap();
    storage.clear_live_favorites()?;
    Ok(Json(ApiResponse::success(())))
}
