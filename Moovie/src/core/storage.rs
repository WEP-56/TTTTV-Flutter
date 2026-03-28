use crate::utils::error::{MoovieError, Result};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::path::PathBuf;

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum SiteHealthStatus {
    Healthy,
    Degraded,
    Unhealthy,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SiteState {
    pub enabled: bool,
    pub last_check: Option<i64>,
    pub is_healthy: Option<bool>,
    #[serde(default)]
    pub health_status: Option<SiteHealthStatus>,
    #[serde(default)]
    pub response_time_ms: Option<i64>,
    #[serde(default)]
    pub status_message: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WatchHistoryItem {
    pub vod_id: String,
    pub source_key: String,
    pub vod_name: String,
    pub vod_pic: Option<String>,
    pub last_play_time: i64,
    pub progress: f64,
    pub episode: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FavoriteItem {
    pub vod_id: String,
    pub source_key: String,
    pub vod_name: String,
    pub vod_pic: Option<String>,
    pub vod_remarks: Option<String>,
    pub vod_actor: Option<String>,
    pub vod_director: Option<String>,
    pub vod_content: Option<String>,
    pub created_time: i64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LiveHistoryItem {
    pub platform: String,
    pub room_id: String,
    pub title: String,
    pub cover: Option<String>,
    pub user_name: Option<String>,
    pub user_avatar: Option<String>,
    pub last_watch_time: i64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LiveFavoriteItem {
    pub platform: String,
    pub room_id: String,
    pub title: String,
    pub cover: Option<String>,
    pub user_name: Option<String>,
    pub user_avatar: Option<String>,
    pub created_time: i64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct StorageData {
    pub site_states: HashMap<String, SiteState>,
    pub watch_history: Vec<WatchHistoryItem>,
    pub favorites: Vec<FavoriteItem>,
    #[serde(default)]
    pub live_history: Vec<LiveHistoryItem>,
    #[serde(default)]
    pub live_favorites: Vec<LiveFavoriteItem>,
    #[serde(default)]
    pub live_cookies: HashMap<String, String>,
}

impl Default for StorageData {
    fn default() -> Self {
        StorageData {
            site_states: HashMap::new(),
            watch_history: Vec::new(),
            favorites: Vec::new(),
            live_history: Vec::new(),
            live_favorites: Vec::new(),
            live_cookies: HashMap::new(),
        }
    }
}

pub struct LocalStorage {
    path: PathBuf,
    data: StorageData,
}

impl LocalStorage {
    pub fn new(path: PathBuf) -> Result<Self> {
        let data = if path.exists() {
            let content = std::fs::read_to_string(&path).map_err(|e| MoovieError::IoError(e))?;
            serde_json::from_str(&content).map_err(|e| MoovieError::JsonError(e))?
        } else {
            StorageData::default()
        };

        Ok(LocalStorage { path, data })
    }

    pub fn save(&self) -> Result<()> {
        if let Some(parent) = self.path.parent() {
            std::fs::create_dir_all(parent).map_err(|e| MoovieError::IoError(e))?;
        }
        let content =
            serde_json::to_string_pretty(&self.data).map_err(|e| MoovieError::JsonError(e))?;
        std::fs::write(&self.path, content).map_err(|e| MoovieError::IoError(e))?;
        Ok(())
    }

    pub fn get_site_state(&self, key: &str) -> SiteState {
        self.data
            .site_states
            .get(key)
            .cloned()
            .unwrap_or(SiteState {
                enabled: true,
                last_check: None,
                is_healthy: None,
                health_status: None,
                response_time_ms: None,
                status_message: None,
            })
    }

    pub fn set_site_state(&mut self, key: &str, state: SiteState) -> Result<()> {
        self.data.site_states.insert(key.to_string(), state);
        self.save()
    }

    pub fn set_site_states_batch<I>(&mut self, states: I) -> Result<()>
    where
        I: IntoIterator<Item = (String, SiteState)>,
    {
        for (key, state) in states {
            self.data.site_states.insert(key, state);
        }
        self.save()
    }

    pub fn get_all_site_states(&self) -> &HashMap<String, SiteState> {
        &self.data.site_states
    }

    pub fn add_watch_history(&mut self, item: WatchHistoryItem) -> Result<()> {
        self.data
            .watch_history
            .retain(|h| h.vod_id != item.vod_id || h.source_key != item.source_key);
        self.data.watch_history.insert(0, item);
        self.data.watch_history.truncate(100);
        self.save()
    }

    pub fn remove_watch_history(&mut self, vod_id: &str, source_key: &str) -> Result<()> {
        self.data
            .watch_history
            .retain(|h| h.vod_id != vod_id || h.source_key != source_key);
        self.save()
    }

    pub fn clear_watch_history(&mut self) -> Result<()> {
        self.data.watch_history.clear();
        self.save()
    }

    pub fn get_watch_history(&self) -> &[WatchHistoryItem] {
        &self.data.watch_history
    }

    pub fn add_favorite(&mut self, item: FavoriteItem) -> Result<()> {
        self.data
            .favorites
            .retain(|f| f.vod_id != item.vod_id || f.source_key != item.source_key);
        self.data.favorites.insert(0, item);
        self.save()
    }

    pub fn remove_favorite(&mut self, vod_id: &str, source_key: &str) -> Result<()> {
        self.data
            .favorites
            .retain(|f| f.vod_id != vod_id || f.source_key != source_key);
        self.save()
    }

    pub fn clear_favorites(&mut self) -> Result<()> {
        self.data.favorites.clear();
        self.save()
    }

    pub fn is_favorited(&self, vod_id: &str, source_key: &str) -> bool {
        self.data
            .favorites
            .iter()
            .any(|f| f.vod_id == vod_id && f.source_key == source_key)
    }

    pub fn get_favorites(&self) -> &[FavoriteItem] {
        &self.data.favorites
    }

    pub fn add_live_history(&mut self, item: LiveHistoryItem) -> Result<()> {
        self.data
            .live_history
            .retain(|h| h.platform != item.platform || h.room_id != item.room_id);
        self.data.live_history.insert(0, item);
        self.data.live_history.truncate(200);
        self.save()
    }

    pub fn remove_live_history(&mut self, platform: &str, room_id: &str) -> Result<()> {
        self.data
            .live_history
            .retain(|h| h.platform != platform || h.room_id != room_id);
        self.save()
    }

    pub fn clear_live_history(&mut self) -> Result<()> {
        self.data.live_history.clear();
        self.save()
    }

    pub fn get_live_history(&self) -> &[LiveHistoryItem] {
        &self.data.live_history
    }

    pub fn add_live_favorite(&mut self, item: LiveFavoriteItem) -> Result<()> {
        self.data
            .live_favorites
            .retain(|f| f.platform != item.platform || f.room_id != item.room_id);
        self.data.live_favorites.insert(0, item);
        self.save()
    }

    pub fn remove_live_favorite(&mut self, platform: &str, room_id: &str) -> Result<()> {
        self.data
            .live_favorites
            .retain(|f| f.platform != platform || f.room_id != room_id);
        self.save()
    }

    pub fn clear_live_favorites(&mut self) -> Result<()> {
        self.data.live_favorites.clear();
        self.save()
    }

    pub fn is_live_favorited(&self, platform: &str, room_id: &str) -> bool {
        self.data
            .live_favorites
            .iter()
            .any(|f| f.platform == platform && f.room_id == room_id)
    }

    pub fn get_live_favorites(&self) -> &[LiveFavoriteItem] {
        &self.data.live_favorites
    }

    pub fn get_live_cookie(&self, platform: &str) -> Option<String> {
        self.data.live_cookies.get(platform).cloned()
    }

    pub fn set_live_cookie(&mut self, platform: &str, cookie: String) -> Result<()> {
        if cookie.trim().is_empty() {
            self.data.live_cookies.remove(platform);
        } else {
            self.data.live_cookies.insert(platform.to_string(), cookie);
        }
        self.save()
    }
}
