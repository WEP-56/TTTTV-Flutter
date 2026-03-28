use serde::Deserialize;
use std::path::PathBuf;

#[derive(Debug, Clone, Deserialize)]
pub struct Config {
    pub server: ServerConfig,
    pub database: DatabaseConfig,
    pub sources: Vec<SourceConfig>,
}

#[derive(Debug, Clone, Deserialize)]
pub struct ServerConfig {
    pub host: String,
    pub port: u16,
}

#[derive(Debug, Clone, Deserialize)]
pub struct DatabaseConfig {
    pub path: PathBuf,
}

#[derive(Debug, Clone, Deserialize)]
pub struct SourceConfig {
    pub key: String,
    pub base_url: String,
    pub enabled: bool,
}

impl Default for Config {
    fn default() -> Self {
        Config {
            server: ServerConfig {
                host: "127.0.0.1".to_string(),
                port: 5007,
            },
            database: DatabaseConfig {
                path: PathBuf::from("moovie.db"),
            },
            sources: vec![SourceConfig {
                key: "yinghua".to_string(),
                base_url: "https://www.yhdm.so/api.php/provide/vod/".to_string(),
                enabled: true,
            }],
        }
    }
}
