use crate::models::{Site, VodItem};
use crate::services::SourceCrawler;
use crate::utils::error::{MoovieError, Result};
use futures::future::join_all;
use std::collections::HashMap;
use std::sync::{Arc, RwLock};
use std::time::Duration;
use tokio::sync::mpsc;
use tracing::info;

/// 根据站点历史响应时间计算动态超时：max(2s, avg * 3)，上限 8s，无数据用 5s。
fn dynamic_timeout(avg_ms: Option<i64>) -> Duration {
    match avg_ms {
        Some(ms) if ms > 0 => {
            let computed = Duration::from_millis((ms * 3) as u64);
            computed.clamp(Duration::from_secs(2), Duration::from_secs(8))
        }
        _ => Duration::from_secs(5),
    }
}

/// 单个站点的搜索结果事件，用于 SSE 流式推送
#[derive(Debug, Clone, serde::Serialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum SearchEvent {
    Start { query: String, total_sources: usize },
    SourceResult { source: String, source_name: String, results: Vec<VodItem> },
    SourceError { source: String, source_name: String, error: String },
    Complete { total_results: usize, completed_sources: usize },
}

#[derive(Debug, Clone)]
pub struct SearchResult {
    pub items: Vec<VodItem>,
    pub filtered_count: usize,
}

#[derive(Clone)]
pub struct SearchService {
    crawler: Arc<dyn SourceCrawler>,
    sites: Arc<RwLock<Vec<Site>>>,
    copyright_keywords: Arc<Vec<String>>,
    category_keywords: Arc<Vec<String>>,
}

impl SearchService {
    pub fn new(
        crawler: Arc<dyn SourceCrawler>,
        sites: Vec<Site>,
        copyright_keywords: Vec<String>,
        category_keywords: Vec<String>,
    ) -> Self {
        SearchService {
            crawler,
            sites: Arc::new(RwLock::new(sites)),
            copyright_keywords: Arc::new(copyright_keywords),
            category_keywords: Arc::new(category_keywords),
        }
    }

    pub fn get_sites(&self) -> Vec<Site> {
        self.sites.read().unwrap().clone()
    }

    pub fn update_sites(&self, sites: Vec<Site>) {
        let mut s = self.sites.write().unwrap();
        *s = sites;
    }

    pub async fn search(
        &self,
        keyword: &str,
        bypass_filter: bool,
        speed_map: HashMap<String, Option<i64>>,
    ) -> Result<SearchResult> {
        info!("开始搜索: {}", keyword);

        let sites = self.sites.read().unwrap().clone();
        let enabled_sites: Vec<_> = sites.iter().filter(|s| s.enabled).cloned().collect();

        if enabled_sites.is_empty() {
            return Ok(SearchResult {
                items: Vec::new(),
                filtered_count: 0,
            });
        }

        let mut tasks = Vec::new();
        for site in enabled_sites {
            let crawler = self.crawler.clone();
            let keyword = keyword.to_string();
            let site_key = site.key.clone();
            let base_url = site.base_url.clone();
            let categories = self.category_keywords.clone();
            let site_timeout = dynamic_timeout(
                speed_map.get(&site_key).copied().flatten()
            );

            let task = tokio::spawn(async move {
                tokio::time::timeout(
                    site_timeout,
                    crawler.search(&base_url, &keyword, &site_key, &categories),
                )
                .await
            });

            tasks.push(task);
        }

        let results = join_all(tasks).await;
        let mut all_items = Vec::new();

        for result in results {
            match result {
                Ok(Ok(Ok(items))) => {
                    info!("站点返回 {} 条结果", items.len());
                    all_items.extend(items);
                }
                Ok(Ok(Err(e))) => {
                    info!("搜索失败: {}", e);
                }
                Ok(Err(_)) => {
                    info!("搜索超时");
                }
                Err(e) => {
                    info!("任务失败: {}", e);
                }
            }
        }

        let filtered_count;
        let items = if !bypass_filter {
            let (filtered, count) = self.filter_copyright_content(all_items);
            filtered_count = count;
            filtered
        } else {
            filtered_count = 0;
            all_items
        };

        let mut items = items;
        items.sort_by(|a, b| match (a.avg_speed_ms, b.avg_speed_ms) {
            (None, None) => std::cmp::Ordering::Equal,
            (None, Some(_)) => std::cmp::Ordering::Greater,
            (Some(_), None) => std::cmp::Ordering::Less,
            (Some(a_ms), Some(b_ms)) => a_ms.cmp(&b_ms),
        });

        Ok(SearchResult {
            items,
            filtered_count,
        })
    }

    /// 流式搜索：每个站点完成后立即通过 channel 发送结果，不等待最慢站点。
    /// `speed_map`: site_key → 历史平均响应时间(ms)，用于动态超时。
    pub fn search_stream(
        &self,
        keyword: &str,
        bypass_filter: bool,
        speed_map: HashMap<String, Option<i64>>,
    ) -> mpsc::Receiver<SearchEvent> {
        let (tx, rx) = mpsc::channel::<SearchEvent>(64);

        let sites = self.sites.read().unwrap().clone();
        let enabled_sites: Vec<Site> = sites.into_iter().filter(|s| s.enabled).collect();
        let total_sources = enabled_sites.len();
        let keyword = keyword.to_string();
        let crawler = self.crawler.clone();
        let copyright_keywords = self.copyright_keywords.clone();
        let category_keywords = self.category_keywords.clone();

        tokio::spawn(async move {
            let _ = tx
                .send(SearchEvent::Start {
                    query: keyword.clone(),
                    total_sources,
                })
                .await;

            let tx = Arc::new(tx);
            let completed = Arc::new(std::sync::atomic::AtomicUsize::new(0));
            let total_results = Arc::new(std::sync::atomic::AtomicUsize::new(0));

            let mut handles = Vec::new();
            for site in enabled_sites {
                let tx = tx.clone();
                let crawler = crawler.clone();
                let keyword = keyword.clone();
                let categories = category_keywords.clone();
                let copyright = copyright_keywords.clone();
                let completed = completed.clone();
                let total_results = total_results.clone();
                let site_timeout = dynamic_timeout(
                    speed_map.get(&site.key).copied().flatten()
                );

                let handle = tokio::spawn(async move {
                    let result = tokio::time::timeout(
                        site_timeout,
                        crawler.search(&site.base_url, &keyword, &site.key, &categories),
                    )
                    .await;

                    let done = completed.fetch_add(1, std::sync::atomic::Ordering::Relaxed) + 1;

                    match result {
                        Ok(Ok(items)) => {
                            let filtered: Vec<VodItem> = if bypass_filter {
                                items
                            } else {
                                items
                                    .into_iter()
                                    .filter(|item| {
                                        !copyright.iter().any(|kw| {
                                            item.vod_name
                                                .to_lowercase()
                                                .contains(&kw.to_lowercase())
                                        })
                                    })
                                    .collect()
                            };
                            total_results.fetch_add(
                                filtered.len(),
                                std::sync::atomic::Ordering::Relaxed,
                            );
                            let _ = tx
                                .send(SearchEvent::SourceResult {
                                    source: site.key.clone(),
                                    source_name: site.key.clone(),
                                    results: filtered,
                                })
                                .await;
                        }
                        Ok(Err(e)) => {
                            let _ = tx
                                .send(SearchEvent::SourceError {
                                    source: site.key.clone(),
                                    source_name: site.key.clone(),
                                    error: e.to_string(),
                                })
                                .await;
                        }
                        Err(_) => {
                            let _ = tx
                                .send(SearchEvent::SourceError {
                                    source: site.key.clone(),
                                    source_name: site.key.clone(),
                                    error: "搜索超时".to_string(),
                                })
                                .await;
                        }
                    }

                    if done == total_sources {
                        let _ = tx
                            .send(SearchEvent::Complete {
                                total_results: total_results
                                    .load(std::sync::atomic::Ordering::Relaxed),
                                completed_sources: done,
                            })
                            .await;
                    }
                });
                handles.push(handle);
            }

            join_all(handles).await;
        });

        rx
    }

    pub async fn get_detail(&self, source_key: &str, vod_id: &str) -> Result<VodItem> {
        info!("获取详情: {} - {}", source_key, vod_id);

        let sites = self.sites.read().unwrap().clone();
        let site = sites
            .iter()
            .find(|s| s.key == source_key && s.enabled)
            .ok_or_else(|| MoovieError::NotFound)?;

        self.crawler
            .get_detail(&site.base_url, vod_id, source_key)
            .await
    }

    fn filter_copyright_content(&self, items: Vec<VodItem>) -> (Vec<VodItem>, usize) {
        if self.copyright_keywords.is_empty() {
            return (items, 0);
        }

        let total_count = items.len();
        let filtered: Vec<_> = items
            .into_iter()
            .filter(|item| {
                !self
                    .copyright_keywords
                    .iter()
                    .any(|kw| item.vod_name.to_lowercase().contains(&kw.to_lowercase()))
            })
            .collect();

        let filtered_count = total_count - filtered.len();
        if filtered_count > 0 {
            info!(
                "版权过滤: 原 {} 条，过滤后 {} 条",
                total_count,
                filtered.len()
            );
        }

        (filtered, filtered_count)
    }
}
