use serde::{Deserialize, Serialize};
use chrono::{DateTime, Utc};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WatchHistory {
    pub id: Option<i64>,
    pub douban_id: Option<String>,
    pub vod_id: String,
    pub title: String,
    pub poster: Option<String>,
    pub episode: Option<String>,
    pub progress: i32,
    pub last_time: f64,
    pub duration: f64,
    pub source: String,
    pub watched_at: DateTime<Utc>,
}
