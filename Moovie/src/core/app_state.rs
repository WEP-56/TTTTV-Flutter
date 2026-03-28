use crate::api::sources::AddSourceRequest;
use crate::api::sources::{AddSourcesBatchFailure, AddSourcesBatchResult, DisableBadSitesResult};
use crate::core::source_config::{ApiSite, SourceConfig};
use crate::core::storage::{LocalStorage, SiteHealthStatus, SiteState};
use crate::models::Site;
use crate::proxy::StreamUrlStore;
use crate::services::{DefaultSourceCrawler, PlayParser, SearchService, SourceCrawler};
use crate::utils::error::{MoovieError, Result};
use futures::stream::{self, StreamExt};
use reqwest::{Client, StatusCode};
use serde::Deserialize;
use std::path::PathBuf;
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};
use url::Url;

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

        let search_service = SearchService::new(crawler, sites.clone(), Vec::new(), Vec::new());

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
                let state = site_states
                    .get(&site.key)
                    .cloned()
                    .unwrap_or_else(|| default_site_state(site.enabled));
                let api_site = source_config.api_site.get(&site.key);
                let health_status = effective_health_status(&state);

                SiteWithStatus {
                    key: site.key.clone(),
                    name: api_site.map(|s| s.name.clone()).unwrap_or(site.key.clone()),
                    base_url: site.base_url.clone(),
                    enabled: state.enabled,
                    last_check: state.last_check,
                    is_healthy: state.is_healthy,
                    health_status,
                    response_time_ms: state.response_time_ms,
                    status_message: state.status_message,
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

    pub async fn check_site_health(&self, key: Option<&str>) -> Result<Vec<SiteWithStatus>> {
        let sites_to_check = {
            let sites = self.sites.lock().unwrap();
            let mut filtered: Vec<Site> = sites
                .iter()
                .filter(|site| key.is_none_or(|target| site.key == target))
                .cloned()
                .collect();

            filtered.sort_by(|a, b| a.key.cmp(&b.key));
            filtered
        };

        if sites_to_check.is_empty() {
            return Err(MoovieError::NotFound);
        }

        let checks = stream::iter(sites_to_check.into_iter().map(|site| {
            let client = self.client.clone();
            async move {
                let result = run_site_health_check(&client, &site.base_url).await;
                (site.key, result)
            }
        }))
        .buffer_unordered(6)
        .collect::<Vec<_>>()
        .await;

        {
            let mut storage = self.storage.lock().unwrap();
            let mut states = Vec::with_capacity(checks.len());

            for (key, result) in &checks {
                let mut state = storage.get_site_state(key);
                state.last_check = Some(result.checked_at);
                state.is_healthy = Some(matches!(result.health_status, SiteHealthStatus::Healthy));
                state.health_status = Some(result.health_status.clone());
                state.response_time_ms = result.response_time_ms;
                state.status_message = result.status_message.clone();
                states.push((key.clone(), state));
            }

            storage.set_site_states_batch(states)?;
        }

        let mut sites = self.get_all_sites();
        if let Some(target) = key {
            sites.retain(|site| site.key == target);
        }
        Ok(sites)
    }

    pub fn disable_bad_sites(&self) -> Result<DisableBadSitesResult> {
        let mut storage = self.storage.lock().unwrap();
        let mut sites = self.sites.lock().unwrap();

        let mut states_to_save = Vec::new();
        let mut disabled = Vec::new();
        let mut already_disabled = Vec::new();
        let mut skipped = Vec::new();

        for site in sites.iter_mut() {
            let mut state = storage.get_site_state(&site.key);
            let health_status = effective_health_status(&state);

            if !matches!(
                health_status,
                Some(SiteHealthStatus::Degraded | SiteHealthStatus::Unhealthy)
            ) {
                skipped.push(site.key.clone());
                continue;
            }

            if !site.enabled {
                already_disabled.push(site.key.clone());
                continue;
            }

            site.enabled = false;
            state.enabled = false;
            states_to_save.push((site.key.clone(), state));
            disabled.push(site.key.clone());
        }

        if !states_to_save.is_empty() {
            storage.set_site_states_batch(states_to_save)?;
            self.search_service.update_sites(sites.clone());
        }

        Ok(DisableBadSitesResult {
            disabled,
            already_disabled,
            skipped,
        })
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
    pub health_status: Option<SiteHealthStatus>,
    pub response_time_ms: Option<i64>,
    pub status_message: Option<String>,
    pub comment: Option<String>,
    pub r18: Option<bool>,
    pub group: Option<String>,
}

#[derive(Debug, Deserialize)]
struct SiteHealthApiResponse {
    code: Option<serde_json::Value>,
    msg: Option<String>,
    list: Option<Vec<serde_json::Value>>,
}

#[derive(Debug, Clone)]
struct SiteHealthCheckResult {
    checked_at: i64,
    health_status: SiteHealthStatus,
    response_time_ms: Option<i64>,
    status_message: Option<String>,
}

fn default_site_state(enabled: bool) -> SiteState {
    SiteState {
        enabled,
        last_check: None,
        is_healthy: None,
        health_status: None,
        response_time_ms: None,
        status_message: None,
    }
}

fn effective_health_status(state: &SiteState) -> Option<SiteHealthStatus> {
    state
        .health_status
        .clone()
        .or_else(|| match state.is_healthy {
            Some(true) => Some(SiteHealthStatus::Healthy),
            Some(false) => Some(SiteHealthStatus::Unhealthy),
            None => None,
        })
}

async fn run_site_health_check(client: &Client, base_url: &str) -> SiteHealthCheckResult {
    const REQUEST_TIMEOUT: Duration = Duration::from_secs(8);
    const DEGRADED_THRESHOLD_MS: i64 = 2500;

    let checked_at = chrono::Utc::now().timestamp_millis();
    let url = match build_site_health_url(base_url) {
        Ok(url) => url,
        Err(error) => {
            return SiteHealthCheckResult {
                checked_at,
                health_status: SiteHealthStatus::Unhealthy,
                response_time_ms: None,
                status_message: Some(error.to_string()),
            };
        }
    };

    let started_at = Instant::now();
    let response = tokio::time::timeout(REQUEST_TIMEOUT, async {
        let response = client.get(url).send().await?;
        let status = response.status();
        let body = response.text().await?;
        Ok::<(StatusCode, String), reqwest::Error>((status, body))
    })
    .await;

    let elapsed_ms = started_at.elapsed().as_millis() as i64;

    match response {
        Err(_) => SiteHealthCheckResult {
            checked_at,
            health_status: SiteHealthStatus::Unhealthy,
            response_time_ms: Some(elapsed_ms),
            status_message: Some(format!("检查超时，耗时 {} ms", elapsed_ms)),
        },
        Ok(Err(error)) => SiteHealthCheckResult {
            checked_at,
            health_status: SiteHealthStatus::Unhealthy,
            response_time_ms: Some(elapsed_ms),
            status_message: Some(error.to_string()),
        },
        Ok(Ok((status, body))) if !status.is_success() => SiteHealthCheckResult {
            checked_at,
            health_status: SiteHealthStatus::Unhealthy,
            response_time_ms: Some(elapsed_ms),
            status_message: Some(format!("HTTP {}", status)),
        },
        Ok(Ok((_, body))) => match serde_json::from_str::<SiteHealthApiResponse>(&body) {
            Ok(api_response) => evaluate_site_health_response(
                checked_at,
                elapsed_ms,
                api_response,
                DEGRADED_THRESHOLD_MS,
            ),
            Err(error) => SiteHealthCheckResult {
                checked_at,
                health_status: SiteHealthStatus::Unhealthy,
                response_time_ms: Some(elapsed_ms),
                status_message: Some(format!("响应解析失败: {}", error)),
            },
        },
    }
}

fn build_site_health_url(base_url: &str) -> Result<Url> {
    let mut url = Url::parse(base_url).map_err(|error| {
        MoovieError::InvalidParameter(format!("无效片源地址 {}: {}", base_url, error))
    })?;

    {
        let mut pairs = url.query_pairs_mut();
        pairs.append_pair("ac", "videolist");
        pairs.append_pair("pg", "1");
        pairs.append_pair("wd", "");
    }

    Ok(url)
}

fn evaluate_site_health_response(
    checked_at: i64,
    elapsed_ms: i64,
    response: SiteHealthApiResponse,
    degraded_threshold_ms: i64,
) -> SiteHealthCheckResult {
    let code = response
        .code
        .as_ref()
        .and_then(read_response_code)
        .unwrap_or(1);

    if ![0, 1, 200].contains(&code) {
        return SiteHealthCheckResult {
            checked_at,
            health_status: SiteHealthStatus::Unhealthy,
            response_time_ms: Some(elapsed_ms),
            status_message: Some(
                response
                    .msg
                    .filter(|msg| !msg.trim().is_empty())
                    .unwrap_or_else(|| format!("接口返回错误码 {}", code)),
            ),
        };
    }

    if response.list.is_none() {
        return SiteHealthCheckResult {
            checked_at,
            health_status: SiteHealthStatus::Unhealthy,
            response_time_ms: Some(elapsed_ms),
            status_message: Some("响应缺少 list 字段".to_string()),
        };
    }

    if elapsed_ms > degraded_threshold_ms {
        return SiteHealthCheckResult {
            checked_at,
            health_status: SiteHealthStatus::Degraded,
            response_time_ms: Some(elapsed_ms),
            status_message: Some(format!("接口可用，但响应较慢: {} ms", elapsed_ms)),
        };
    }

    SiteHealthCheckResult {
        checked_at,
        health_status: SiteHealthStatus::Healthy,
        response_time_ms: Some(elapsed_ms),
        status_message: None,
    }
}

fn read_response_code(value: &serde_json::Value) -> Option<i64> {
    match value {
        serde_json::Value::Number(number) => number.as_i64(),
        serde_json::Value::String(text) => text.parse::<i64>().ok(),
        _ => None,
    }
}
