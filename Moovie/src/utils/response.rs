use serde::{Deserialize, Serialize};
use axum::{
    http::StatusCode,
    response::{IntoResponse, Response},
    Json,
};
use super::error::MoovieError;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ApiResponse<T> {
    pub success: bool,
    pub data: Option<T>,
    pub message: Option<String>,
    pub error: Option<String>,
}

impl<T> ApiResponse<T> {
    pub fn success(data: T) -> Self {
        ApiResponse {
            success: true,
            data: Some(data),
            message: None,
            error: None,
        }
    }

    pub fn success_with_message(data: T, message: &str) -> Self {
        ApiResponse {
            success: true,
            data: Some(data),
            message: Some(message.to_string()),
            error: None,
        }
    }

    pub fn error(message: &str) -> Self {
        ApiResponse {
            success: false,
            data: None,
            message: None,
            error: Some(message.to_string()),
        }
    }
}

pub type ApiResult<T> = std::result::Result<Json<ApiResponse<T>>, MoovieError>;

impl IntoResponse for MoovieError {
    fn into_response(self) -> Response {
        let (status, error_response) = match self {
            MoovieError::NotFound => (
                StatusCode::NOT_FOUND,
                ApiResponse::<()>::error("资源未找到"),
            ),
            MoovieError::InvalidParameter(msg) => (
                StatusCode::BAD_REQUEST,
                ApiResponse::<()>::error(&msg),
            ),
            _ => (
                StatusCode::INTERNAL_SERVER_ERROR,
                ApiResponse::<()>::error(&self.to_string()),
            ),
        };

        (status, Json(error_response)).into_response()
    }
}
