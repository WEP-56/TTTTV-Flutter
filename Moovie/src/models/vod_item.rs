use serde::{Deserialize, Serialize};
use chrono::{DateTime, Utc};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VodItem {
    pub source_key: String,
    pub vod_id: String,
    pub vod_name: String,
    pub vod_sub: Option<String>,
    pub vod_en: Option<String>,
    pub vod_tag: Option<String>,
    pub vod_class: Option<String>,
    pub vod_pic: Option<String>,
    pub vod_actor: Option<String>,
    pub vod_director: Option<String>,
    pub vod_blurb: Option<String>,
    pub vod_remarks: Option<String>,
    pub vod_pubdate: Option<String>,
    pub vod_total: Option<String>,
    pub vod_serial: Option<String>,
    pub vod_area: Option<String>,
    pub vod_lang: Option<String>,
    pub vod_year: Option<String>,
    pub vod_duration: Option<String>,
    pub vod_time: Option<String>,
    pub vod_douban_id: Option<String>,
    pub vod_content: Option<String>,
    pub vod_play_url: String,
    pub type_name: Option<String>,
    pub last_visited_at: Option<DateTime<Utc>>,
    pub avg_speed_ms: Option<i32>,
    pub sample_count: Option<i32>,
    pub failed_count: Option<i32>,
}

impl VodItem {
    pub fn get_genres(&self) -> Vec<String> {
        self.vod_class
            .as_ref()
            .map(|s| {
                s.split(',')
                    .map(|s| s.trim().to_string())
                    .filter(|s| !s.is_empty())
                    .collect()
            })
            .unwrap_or_default()
    }

    pub fn get_directors(&self) -> Vec<String> {
        self.vod_director
            .as_ref()
            .map(|s| {
                s.split(',')
                    .map(|s| s.trim().to_string())
                    .filter(|s| !s.is_empty())
                    .collect()
            })
            .unwrap_or_default()
    }

    pub fn get_actors(&self) -> Vec<String> {
        self.vod_actor
            .as_ref()
            .map(|s| {
                s.split(',')
                    .map(|s| s.trim().to_string())
                    .filter(|s| !s.is_empty())
                    .collect()
            })
            .unwrap_or_default()
    }
}
