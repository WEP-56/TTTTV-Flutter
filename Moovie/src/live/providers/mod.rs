use async_trait::async_trait;

use super::models::{LivePlayQuality, LivePlayUrl, LiveRoomDetail, LiveRoomItem};
use crate::utils::error::Result;

pub mod bilibili;
pub mod douyin;
mod douyin_abogus_native;
pub mod douyu;
pub mod huya;

#[async_trait]
pub trait LiveProvider: Send + Sync {
    fn id(&self) -> &'static str;
    fn name(&self) -> &'static str;

    async fn recommend_rooms(&self, page: i32) -> Result<Vec<LiveRoomItem>>;
    async fn search_rooms(&self, keyword: &str, page: i32) -> Result<Vec<LiveRoomItem>>;
    async fn room_detail(&self, room_id: &str) -> Result<LiveRoomDetail>;
    async fn play_qualities(&self, room_id: &str) -> Result<Vec<LivePlayQuality>>;
    async fn play_urls(&self, room_id: &str, quality_id: &str) -> Result<LivePlayUrl>;
}
