use thiserror::Error;

#[derive(Error, Debug)]
pub enum MoovieError {
    #[error("HTTP请求错误: {0}")]
    HttpError(#[from] reqwest::Error),

    #[error("JSON解析错误: {0}")]
    JsonError(#[from] serde_json::Error),

    #[error("数据库错误: {0}")]
    DbError(#[from] sqlx::Error),

    #[error("IO错误: {0}")]
    IoError(#[from] std::io::Error),

    #[error("资源站搜索失败: {0}")]
    SourceSearchError(String),

    #[error("视频详情获取失败: {0}")]
    DetailError(String),

    #[error("未找到视频")]
    NotFound,

    #[error("无效的参数: {0}")]
    InvalidParameter(String),

    #[error("配置错误: {0}")]
    ConfigError(String),

    #[error("未知错误: {0}")]
    Unknown(String),
}

pub type Result<T> = std::result::Result<T, MoovieError>;
