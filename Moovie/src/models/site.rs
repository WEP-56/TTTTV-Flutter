use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Site {
    pub id: Option<i64>,
    pub key: String,
    pub base_url: String,
    pub enabled: bool,
}
