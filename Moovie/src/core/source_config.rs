use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::path::Path;
use crate::models::Site;
use crate::utils::error::{Result, MoovieError};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SourceConfig {
    pub cache_time: Option<i64>,
    pub api_site: HashMap<String, ApiSite>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ApiSite {
    pub name: String,
    pub api: String,
    pub detail: String,
    #[serde(default)]
    pub enabled: bool,
    #[serde(default)]
    pub r18: bool,
    #[serde(default = "default_group")]
    pub group: String,
    #[serde(rename = "_comment")]
    pub comment: Option<String>,
}

fn default_group() -> String {
    "影视".to_string()
}

impl SourceConfig {
    pub fn load_from_file<P: AsRef<Path>>(path: P) -> Result<Self> {
        let content = std::fs::read_to_string(&path)
            .map_err(|e| MoovieError::ConfigError(format!("无法读取配置文件: {}", e)))?;
        
        serde_json::from_str(&content)
            .map_err(|e| MoovieError::ConfigError(format!("解析配置文件失败: {}", e)))
    }

    pub fn to_sites(&self) -> Vec<Site> {
        self.api_site
            .iter()
            .map(|(key, api_site)| Site {
                id: None,
                key: key.clone(),
                base_url: api_site.api.clone(),
                enabled: api_site.enabled,
            })
            .collect()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_parse_sources_config() {
        let json = r#"
        {
            "cache_time": 7200,
            "api_site": {
                "test.com": {
                    "name": "🎬测试资源",
                    "api": "https://test.com/api.php/provide/vod",
                    "detail": "https://test.com"
                }
            }
        }
        "#;
        
        let config: SourceConfig = serde_json::from_str(json).unwrap();
        assert_eq!(config.cache_time, Some(7200));
        assert!(config.api_site.contains_key("test.com"));
        
        let sites = config.to_sites();
        assert_eq!(sites.len(), 1);
        assert_eq!(sites[0].key, "test.com");
    }
}
