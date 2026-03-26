use axum::{
    extract::{State, Query},
    routing::{get, post, delete},
    Json, Router,
};
use crate::core::{AppState, SiteWithStatus};
use crate::utils::response::{ApiResponse, ApiResult};
use serde::{Deserialize, Serialize};
use crate::utils::error::MoovieError;

#[derive(Deserialize)]
pub struct ToggleSiteQuery {
    pub key: String,
    pub enabled: bool,
}

#[derive(Deserialize)]
pub struct CheckSiteQuery {
    pub key: Option<String>,
}

#[derive(Deserialize)]
pub struct AddSourceRequest {
    pub key: String,
    pub name: String,
    pub api: String,
    pub detail: String,
    pub group: Option<String>,
    pub r18: Option<bool>,
    pub comment: Option<String>,
}

#[derive(Deserialize)]
pub struct DeleteSourceRequest {
    pub key: String,
}

#[derive(Deserialize)]
pub struct RemoteSourcesQuery {
    pub url: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RemoteSource {
    #[serde(default)]
    pub key: String,
    pub name: String,
    pub api: String,
    pub detail: String,
    pub group: Option<String>,
    pub r18: Option<bool>,
    #[serde(alias = "_comment")]
    pub comment: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RemoteSourcesResponse {
    pub url: String,
    pub sources: Vec<RemoteSource>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AddSourcesBatchResult {
    pub added: Vec<String>,
    pub skipped_existing: Vec<String>,
    pub failed: Vec<AddSourcesBatchFailure>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AddSourcesBatchFailure {
    pub key: String,
    pub error: String,
}

pub fn router() -> Router<AppState> {
    Router::new()
        .route("/", get(get_sites))
        .route("/toggle", get(toggle_site).post(toggle_site))
        .route("/check", get(check_sites))
        .route("/add", post(add_source))
        .route("/add_batch", post(add_sources_batch))
        .route("/delete", delete(delete_source))
        .route("/remote", get(get_remote_sources))
}

pub async fn get_sites(
    State(state): State<AppState>,
) -> ApiResult<Vec<SiteWithStatus>> {
    let sites = state.get_all_sites();
    Ok(Json(ApiResponse::success(sites)))
}

pub async fn toggle_site(
    State(state): State<AppState>,
    Query(query): Query<ToggleSiteQuery>,
) -> ApiResult<()> {
    state.set_site_enabled(&query.key, query.enabled)?;
    Ok(Json(ApiResponse::success(())))
}

pub async fn check_sites(
    State(state): State<AppState>,
    Query(query): Query<CheckSiteQuery>,
) -> ApiResult<Vec<SiteWithStatus>> {
    let mut sites = state.get_all_sites();
    
    if let Some(key) = query.key {
        sites.retain(|s| s.key == key);
    }

    Ok(Json(ApiResponse::success(sites)))
}

pub async fn add_source(
    State(state): State<AppState>,
    Json(request): Json<AddSourceRequest>,
) -> ApiResult<()> {
    state.add_custom_source(request)?;
    Ok(Json(ApiResponse::success(())))
}

pub async fn add_sources_batch(
    State(state): State<AppState>,
    Json(requests): Json<Vec<AddSourceRequest>>,
) -> ApiResult<AddSourcesBatchResult> {
    let result = state.add_custom_sources_batch(requests)?;
    Ok(Json(ApiResponse::success(result)))
}

pub async fn delete_source(
    State(state): State<AppState>,
    Query(query): Query<DeleteSourceRequest>,
) -> ApiResult<()> {
    state.delete_custom_source(&query.key)?;
    Ok(Json(ApiResponse::success(())))
}

const DEFAULT_REMOTE_SOURCE_INDEX_URLS: [&str; 3] = [
    "https://raw.githubusercontent.com/WEP-56/TTTTV-config/main/sources.json",
    "https://raw.githubusercontent.com/WEP-56/TTTTV-config/main/index.json",
    "https://raw.githubusercontent.com/WEP-56/TTTTV-config/main/indexes/all.json",
];

#[derive(Debug, Clone, Deserialize)]
struct RemoteSourcesEnvelope {
    pub sources: Vec<RemoteSource>,
}

pub async fn get_remote_sources(
    State(state): State<AppState>,
    Query(query): Query<RemoteSourcesQuery>,
) -> ApiResult<RemoteSourcesResponse> {
    let (url, sources) = fetch_remote_sources(&state, query.url).await?;
    Ok(Json(ApiResponse::success(RemoteSourcesResponse { url, sources })))
}

async fn fetch_remote_sources(
    state: &AppState,
    override_url: Option<String>,
) -> Result<(String, Vec<RemoteSource>), MoovieError> {
    let (strict, candidates): (bool, Vec<String>) = match override_url {
        Some(url) => {
            if !url.starts_with("https://") {
                return Err(MoovieError::InvalidParameter(
                    "url 必须以 https:// 开头".to_string(),
                ));
            }
            (true, vec![url])
        }
        None => (
            false,
            DEFAULT_REMOTE_SOURCE_INDEX_URLS
                .iter()
                .map(|s| s.to_string())
                .collect(),
        ),
    };

    let mut last_err: Option<String> = None;

    for url in candidates {
        let resp = match state.client.get(&url).send().await {
            Ok(r) => r,
            Err(e) => {
                if strict {
                    return Err(e.into());
                }
                last_err = Some(e.to_string());
                continue;
            }
        };

        if !resp.status().is_success() {
            if strict {
                return Err(MoovieError::ConfigError(format!(
                    "远程仓库返回 {}: {}",
                    resp.status(),
                    url
                )));
            }
            continue;
        }

        let text = match resp.text().await {
            Ok(t) => t,
            Err(e) => {
                if strict {
                    return Err(e.into());
                }
                last_err = Some(e.to_string());
                continue;
            }
        };

        let sources = parse_remote_sources(&text);
        match sources {
            Ok(list) => return Ok((url, list)),
            Err(e) => {
                if strict {
                    return Err(e);
                }
                last_err = Some(e.to_string());
                continue;
            }
        }
    }

    Err(MoovieError::ConfigError(format!(
        "远程资源站配置获取失败{}",
        last_err
            .map(|e| format!("（最后错误：{}）", e))
            .unwrap_or_default()
    )))
}

fn parse_remote_sources(text: &str) -> Result<Vec<RemoteSource>, MoovieError> {
    if let Ok(list) = serde_json::from_str::<Vec<RemoteSource>>(text) {
        return Ok(normalize_remote_sources(list));
    }

    if let Ok(envelope) = serde_json::from_str::<RemoteSourcesEnvelope>(text) {
        return Ok(normalize_remote_sources(envelope.sources));
    }

    let value: serde_json::Value = serde_json::from_str(text)?;
    if let Some(sources) = value.get("api_site") {
        let mut list = Vec::new();
        let obj = sources
            .as_object()
            .ok_or_else(|| MoovieError::ConfigError("api_site 不是对象".to_string()))?;
        for (key, v) in obj {
            let mut src: RemoteSource = serde_json::from_value(v.clone())?;
            src.key = key.clone();
            list.push(src);
        }
        return Ok(normalize_remote_sources(list));
    }

    Err(MoovieError::ConfigError(
        "远程配置格式不支持（需要数组、sources 字段、或 api_site 结构）".to_string(),
    ))
}

fn normalize_remote_sources(mut list: Vec<RemoteSource>) -> Vec<RemoteSource> {
    list.retain(|s| {
        !s.key.trim().is_empty() && !s.name.trim().is_empty() && !s.api.trim().is_empty()
    });

    for s in &mut list {
        if s.r18.is_none() {
            let group_is_r18 = s.group.as_deref() == Some("R18");
            let name_is_r18 = s.name.contains("🔞") || s.name.to_ascii_uppercase().contains("R18");
            if group_is_r18 || name_is_r18 {
                s.r18 = Some(true);
            }
        }

        if s.group.is_none() && s.r18.unwrap_or(false) {
            s.group = Some("R18".to_string());
        }
    }

    list
}
