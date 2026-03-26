use axum::{
    extract::State,
    routing::{get, post, delete},
    Json, Router,
};
use axum::extract::Query;
use chrono::Utc;
use serde::{Deserialize, Serialize};

use crate::core::app_state::AppState;
use crate::core::storage::FavoriteItem;
use crate::utils::response::{ApiResponse, ApiResult};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AddFavoriteRequest {
    pub vod_id: String,
    pub source_key: String,
    pub vod_name: String,
    pub vod_pic: Option<String>,
    pub vod_remarks: Option<String>,
    pub vod_actor: Option<String>,
    pub vod_director: Option<String>,
    pub vod_content: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DeleteFavoriteRequest {
    pub vod_id: String,
    pub source_key: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CheckFavoriteRequest {
    pub vod_id: String,
    pub source_key: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CheckFavoriteResponse {
    pub is_favorited: bool,
}

pub fn router() -> Router<AppState> {
    Router::new()
        .route("/", get(get_favorites))
        .route("/", post(add_favorite))
        .route("/", delete(delete_favorite))
        .route("/check", get(check_favorite))
        .route("/clear", delete(clear_favorites))
}

pub async fn get_favorites(
    State(state): State<AppState>,
) -> ApiResult<Vec<FavoriteItem>> {
    let storage = state.storage.lock().unwrap();
    let favorites = storage.get_favorites().to_vec();
    Ok(Json(ApiResponse::success(favorites)))
}

pub async fn add_favorite(
    State(state): State<AppState>,
    Json(request): Json<AddFavoriteRequest>,
) -> ApiResult<()> {
    let mut storage = state.storage.lock().unwrap();
    
    let item = FavoriteItem {
        vod_id: request.vod_id,
        source_key: request.source_key,
        vod_name: request.vod_name,
        vod_pic: request.vod_pic,
        vod_remarks: request.vod_remarks,
        vod_actor: request.vod_actor,
        vod_director: request.vod_director,
        vod_content: request.vod_content,
        created_time: Utc::now().timestamp(),
    };
    
    storage.add_favorite(item)?;
    
    Ok(Json(ApiResponse::success(())))
}

pub async fn delete_favorite(
    State(state): State<AppState>,
    Query(query): Query<DeleteFavoriteRequest>,
) -> ApiResult<()> {
    let mut storage = state.storage.lock().unwrap();
    storage.remove_favorite(&query.vod_id, &query.source_key)?;
    Ok(Json(ApiResponse::success(())))
}

pub async fn check_favorite(
    State(state): State<AppState>,
    Query(query): Query<CheckFavoriteRequest>,
) -> ApiResult<CheckFavoriteResponse> {
    let storage = state.storage.lock().unwrap();
    let is_favorited = storage.is_favorited(&query.vod_id, &query.source_key);
    Ok(Json(ApiResponse::success(CheckFavoriteResponse { is_favorited })))
}

pub async fn clear_favorites(
    State(state): State<AppState>,
) -> ApiResult<()> {
    let mut storage = state.storage.lock().unwrap();
    storage.clear_favorites()?;
    Ok(Json(ApiResponse::success(())))
}