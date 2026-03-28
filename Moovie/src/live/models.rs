use serde::{Deserialize, Serialize};
use std::collections::HashMap;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LivePlatformInfo {
    pub id: String,
    pub name: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LiveRoomItem {
    pub platform: String,
    pub room_id: String,
    pub title: String,
    pub cover: String,
    pub user_name: String,
    pub online: i64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LiveRoomDetail {
    pub platform: String,
    pub room_id: String,
    pub title: String,
    pub cover: String,
    pub user_name: String,
    pub user_avatar: String,
    pub online: i64,
    pub introduction: Option<String>,
    pub notice: Option<String>,
    pub status: bool,
    pub is_record: bool,
    pub url: String,
    pub show_time: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LivePlayQuality {
    pub id: String,
    pub name: String,
    pub sort: i32,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LivePlayUrl {
    pub urls: Vec<String>,
    pub headers: Option<HashMap<String, String>>,
    pub url_type: Option<String>,
    pub expires_at: Option<i64>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LiveMessageColor {
    pub r: u8,
    pub g: u8,
    pub b: u8,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum LiveMessageType {
    Chat,
    Gift,
    Online,
    SuperChat,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LiveMessage {
    #[serde(rename = "type")]
    pub kind: LiveMessageType,
    pub user_name: String,
    pub message: String,
    pub color: LiveMessageColor,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub data: Option<serde_json::Value>,
}
