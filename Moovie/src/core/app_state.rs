use crate::services::{SearchService, PlayParser, SourceCrawler, DefaultSourceCrawler};
use crate::models::Site;
use crate::core::storage::{LocalStorage, SiteState};
use crate::core::source_config::{SourceConfig, ApiSite};
use crate::api::sources::AddSourceRequest;
use crate::api::sources::{AddSourcesBatchFailure, AddSourcesBatchResult};
use crate::proxy::{StreamUrlStore, ProxyServerHandle};
use std::sync::{Arc, Mutex};
use reqwest::Client;
use std::path::PathBuf;
use crate::utils::error::{Result, MoovieError};

#[derive(Clone)]
pub struct AppState {
    pub search_service: Arc<SearchService>,
    pub play_parser: Arc<PlayParser>,
    pub source_config: Arc<Mutex<SourceConfig>>,
    pub storage: Arc<Mutex<LocalStorage>>,
    pub sites: Arc<Mutex<Vec<Site>>>,
    pub client: Client,
    pub stream_url_store: StreamUrlStore,
    pub proxy_server_handle: Arc<Mutex<Option<actix_web::dev::ServerHandle>>>,
    config_path: PathBuf,
}

impl AppState {
    pub async fn new(
        mut sites: Vec<Site>,
        source_config: SourceConfig,
        storage: LocalStorage,
        config_path: PathBuf,
    ) -> Self {
        let site_states = storage.get_all_site_states();
        for site in &mut sites {
            if let Some(state) = site_states.get(&site.key) {
                site.enabled = state.enabled;
            }
        }

        let client = Client::builder()
            .timeout(std::time::Duration::from_secs(30))
            .user_agent("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36")
            .build()
            .expect("Failed to create HTTP client");

        let crawler: Arc<dyn SourceCrawler> = Arc::new(DefaultSourceCrawler::new(
            std::time::Duration::from_secs(10),
        ));

        let search_service = SearchService::new(
            crawler,
            sites.clone(),
            Vec::new(),
            Vec::new(),
        );

        let play_parser = PlayParser::new();

        AppState {
            search_service: Arc::new(search_service),
            play_parser: Arc::new(play_parser),
            source_config: Arc::new(Mutex::new(source_config)),
            storage: Arc::new(Mutex::new(storage)),
            sites: Arc::new(Mutex::new(sites)),
            client,
            stream_url_store: StreamUrlStore::default(),
            proxy_server_handle: Arc::new(Mutex::new(None)),
            config_path,
        }
    }

    pub fn get_all_sites(&self) -> Vec<SiteWithStatus> {
        let sites = self.sites.lock().unwrap();
        let storage = self.storage.lock().unwrap();
        let source_config = self.source_config.lock().unwrap();
        let site_states = storage.get_all_site_states();
        
        sites
            .iter()
            .map(|site| {
                let state = site_states.get(&site.key).cloned().unwrap_or(SiteState {
                    enabled: site.enabled,
                    last_check: None,
                    is_healthy: None,
                });
                let api_site = source_config.api_site.get(&site.key);
                
                SiteWithStatus {
                    key: site.key.clone(),
                    name: api_site.map(|s| s.name.clone()).unwrap_or(site.key.clone()),
                    base_url: site.base_url.clone(),
                    enabled: state.enabled,
                    last_check: state.last_check,
                    is_healthy: state.is_healthy,
                    comment: api_site.and_then(|s| s.comment.clone()),
                    r18: api_site.map(|s| s.r18),
                    group: api_site.map(|s| s.group.clone()),
                }
            })
            .collect()
    }

    pub fn set_site_enabled(&self, key: &str, enabled: bool) -> Result<()> {
        let mut storage = self.storage.lock().unwrap();
        let mut state = storage.get_site_state(key);
        state.enabled = enabled;
        storage.set_site_state(key, state)?;
        
        let mut sites = self.sites.lock().unwrap();
        if let Some(site) = sites.iter_mut().find(|s| s.key == key) {
            site.enabled = enabled;
        }
        
        self.search_service.update_sites(sites.clone());
        
        Ok(())
    }

    pub fn add_custom_source(&self, request: AddSourceRequest) -> Result<()> {
        let mut source_config = self.source_config.lock().unwrap();
        
        if source_config.api_site.contains_key(&request.key) {
            return Err(MoovieError::ConfigError("源已存在".to_string()));
        }

        let api_url = request.api.clone();
        let is_r18 = request.r18.unwrap_or(false);
        let group = request.group.unwrap_or_else(|| {
            if is_r18 {
                "R18".to_string()
            } else {
                "自定义".to_string()
            }
        });
        
        let api_site = ApiSite {
            name: request.name,
            api: request.api,
            detail: request.detail,
            enabled: true,
            r18: is_r18,
            group,
            comment: request.comment.or_else(|| Some("自定义添加".to_string())),
        };

        source_config.api_site.insert(request.key.clone(), api_site);

        let mut sites = self.sites.lock().unwrap();
        let new_site = Site {
            id: None,
            key: request.key,
            base_url: api_url,
            enabled: true,
        };
        sites.push(new_site.clone());

        self.search_service.update_sites(sites.clone());

        self.save_source_config(&source_config)?;

        Ok(())
    }

    pub fn add_custom_sources_batch(
        &self,
        requests: Vec<AddSourceRequest>,
    ) -> Result<AddSourcesBatchResult> {
        let mut source_config = self.source_config.lock().unwrap();
        let mut sites = self.sites.lock().unwrap();

        let mut result = AddSourcesBatchResult {
            added: Vec::new(),
            skipped_existing: Vec::new(),
            failed: Vec::new(),
        };

        for request in requests {
            if request.key.trim().is_empty() {
                result.failed.push(AddSourcesBatchFailure {
                    key: request.key,
                    error: "key 不能为空".to_string(),
                });
                continue;
            }

            if source_config.api_site.contains_key(&request.key) {
                result.skipped_existing.push(request.key);
                continue;
            }

            let api_url = request.api.clone();
            let is_r18 = request.r18.unwrap_or(false);
            let group = request.group.unwrap_or_else(|| {
                if is_r18 {
                    "R18".to_string()
                } else {
                    "自定义".to_string()
                }
            });
            let api_site = ApiSite {
                name: request.name,
                api: request.api,
                detail: request.detail,
                enabled: true,
                r18: is_r18,
                group,
                comment: request.comment,
            };

            source_config.api_site.insert(request.key.clone(), api_site);

            sites.push(Site {
                id: None,
                key: request.key.clone(),
                base_url: api_url,
                enabled: true,
            });

            result.added.push(request.key);
        }

        self.search_service.update_sites(sites.clone());
        self.save_source_config(&source_config)?;

        Ok(result)
    }

    pub fn delete_custom_source(&self, key: &str) -> Result<()> {
        let mut source_config = self.source_config.lock().unwrap();
        
        if !source_config.api_site.contains_key(key) {
            return Err(MoovieError::ConfigError("源不存在".to_string()));
        }

        source_config.api_site.remove(key);

        let mut sites = self.sites.lock().unwrap();
        sites.retain(|s| s.key != key);

        self.search_service.update_sites(sites.clone());

        self.save_source_config(&source_config)?;

        Ok(())
    }

    fn save_source_config(&self, config: &SourceConfig) -> Result<()> {
        let json = serde_json::to_string_pretty(config)
            .map_err(|e| MoovieError::ConfigError(format!("序列化配置失败: {}", e)))?;
        
        std::fs::write(&self.config_path, json)
            .map_err(|e| MoovieError::ConfigError(format!("保存配置失败: {}", e)))?;
        
        Ok(())
    }
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct SiteWithStatus {
    pub key: String,
    pub name: String,
    pub base_url: String,
    pub enabled: bool,
    pub last_check: Option<i64>,
    pub is_healthy: Option<bool>,
    pub comment: Option<String>,
    pub r18: Option<bool>,
    pub group: Option<String>,
}
