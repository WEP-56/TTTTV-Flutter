pub mod api;
pub mod core;
pub mod live;
pub mod models;
pub mod proxy;
pub mod services;
pub mod utils;

use axum::{
    routing::get,
    Router,
};
use core::{AppState, LocalStorage, SourceConfig};
use directories::ProjectDirs;
use std::net::{Ipv4Addr, SocketAddr};
use std::path::{Path, PathBuf};
use tower_http::cors::{Any, CorsLayer};
use utils::error::Result;

pub const DEFAULT_SOURCES_JSON: &str = include_str!("../config/sources.json");

#[derive(Debug, Clone, Default)]
pub struct AppBootstrapOptions {
    pub config_path: Option<PathBuf>,
    pub storage_path: Option<PathBuf>,
}

#[derive(Debug, Clone)]
pub struct RuntimePaths {
    pub config_path: PathBuf,
    pub storage_path: PathBuf,
}

#[derive(Debug, Clone)]
pub struct LocalServerOptions {
    pub addr: SocketAddr,
    pub app: AppBootstrapOptions,
}

impl Default for LocalServerOptions {
    fn default() -> Self {
        Self {
            addr: default_server_addr(),
            app: AppBootstrapOptions::default(),
        }
    }
}

pub fn default_server_addr() -> SocketAddr {
    SocketAddr::from((Ipv4Addr::LOCALHOST, 5007))
}

pub fn init_tracing() {
    let _ = tracing_subscriber::fmt()
        .with_env_filter(tracing_subscriber::EnvFilter::from_default_env())
        .try_init();
}

pub fn resolve_runtime_paths(options: &AppBootstrapOptions) -> RuntimePaths {
    RuntimePaths {
        config_path: resolve_config_path(options.config_path.clone()),
        storage_path: resolve_storage_path(options.storage_path.clone()),
    }
}

pub fn resolve_config_path(override_path: Option<PathBuf>) -> PathBuf {
    if let Some(path) = override_path {
        return path;
    }

    let exe_path = std::env::current_exe().ok();
    let exe_dir = exe_path.as_ref().and_then(|path| path.parent());

    let cwd_config = PathBuf::from("config/sources.json");
    if cwd_config.exists() {
        return cwd_config;
    }

    if let Some(dir) = exe_dir {
        let sibling_config = dir.join("config/sources.json");
        if sibling_config.exists() {
            return sibling_config;
        }

        let bundle_resources_config = dir.join("../resources/config/sources.json");
        if bundle_resources_config.exists() {
            return bundle_resources_config;
        }

        let flat_resources_config = dir.join("resources/config/sources.json");
        if flat_resources_config.exists() {
            return flat_resources_config;
        }
    }

    if let Some(project_dirs) = ProjectDirs::from("com", "ttttv", "app") {
        let config_dir = project_dirs.config_dir();
        if !config_dir.exists() {
            let _ = std::fs::create_dir_all(config_dir);
        }
        return config_dir.join("sources.json");
    }

    cwd_config
}

pub fn resolve_storage_path(override_path: Option<PathBuf>) -> PathBuf {
    if let Some(path) = override_path {
        return path;
    }

    let local_data = PathBuf::from("data/storage.json");
    if local_data.exists() {
        return local_data;
    }

    if let Some(project_dirs) = ProjectDirs::from("com", "ttttv", "app") {
        let data_dir = project_dirs.data_dir();
        if !data_dir.exists() {
            let _ = std::fs::create_dir_all(data_dir);
        }
        return data_dir.join("storage.json");
    }

    local_data
}

pub async fn build_app_state(options: &AppBootstrapOptions) -> Result<AppState> {
    let paths = resolve_runtime_paths(options);
    tracing::info!("Using config path: {:?}", paths.config_path);
    tracing::info!("Using storage path: {:?}", paths.storage_path);

    let source_config = load_or_create_source_config(&paths.config_path);
    tracing::info!("Loaded {} configured sources", source_config.api_site.len());

    ensure_parent_dir(&paths.storage_path)?;
    let storage = LocalStorage::new(paths.storage_path.clone())?;

    let sites = source_config.to_sites();
    let enabled_count = sites.iter().filter(|site| site.enabled).count();
    tracing::info!("Loaded {} enabled sites", enabled_count);

    Ok(AppState::new(sites, source_config, storage, paths.config_path).await)
}

pub fn build_router(app_state: AppState) -> Router {
    let cors = CorsLayer::new()
        .allow_origin(Any)
        .allow_methods(Any)
        .allow_headers(Any);

    Router::new()
        .route("/health", get(api::health::health_check))
        .route("/api/search", get(api::search::search))
        .route("/api/detail", get(api::search::get_detail))
        .route("/api/play/parse", get(api::play::parse_play_url))
        .nest("/api/sources", api::sources::router())
        .nest("/api/live", api::live::router())
        .nest("/api/history", api::history::router())
        .nest("/api/favorites", api::favorites::router())
        .route("/api/douban/search", get(api::douban::douban_search))
        .route("/api/douban/chart", get(api::douban::douban_chart_top_list))
        .layer(cors)
        .with_state(app_state)
}

pub async fn build_app(options: &AppBootstrapOptions) -> Result<Router> {
    let app_state = build_app_state(options).await?;
    Ok(build_router(app_state))
}

pub async fn start_local_server(options: LocalServerOptions) -> anyhow::Result<()> {
    let addr = options.addr;
    let app = build_app(&options.app).await?;

    tracing::info!("Moovie backend listening on http://{}", addr);

    let listener = tokio::net::TcpListener::bind(addr).await?;
    axum::serve(listener, app).await?;
    Ok(())
}

fn load_or_create_source_config(config_path: &Path) -> SourceConfig {
    match SourceConfig::load_from_file(config_path) {
        Ok(config) => config,
        Err(error) => {
            tracing::warn!("Failed to load config from {:?}: {}", config_path, error);
            tracing::info!("Creating default config at {:?}", config_path);

            if let Err(create_error) = ensure_parent_dir(config_path) {
                tracing::error!(
                    "Failed to create config directory for {:?}: {}",
                    config_path,
                    create_error
                );
            }

            if let Err(write_error) = std::fs::write(config_path, DEFAULT_SOURCES_JSON) {
                tracing::error!("Failed to write default config: {}", write_error);
            }

            serde_json::from_str(DEFAULT_SOURCES_JSON).expect("Default config is invalid")
        }
    }
}

fn ensure_parent_dir(path: &Path) -> std::io::Result<()> {
    if let Some(parent) = path.parent() {
        std::fs::create_dir_all(parent)?;
    }
    Ok(())
}
