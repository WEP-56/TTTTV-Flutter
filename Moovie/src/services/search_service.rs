use crate::models::{Site, VodItem};
use crate::services::SourceCrawler;
use crate::utils::error::{MoovieError, Result};
use futures::future::join_all;
use std::sync::{Arc, Mutex};
use std::time::Duration;
use tracing::info;

#[derive(Debug, Clone)]
pub struct SearchResult {
    pub items: Vec<VodItem>,
    pub filtered_count: usize,
}

#[derive(Clone)]
pub struct SearchService {
    crawler: Arc<dyn SourceCrawler>,
    sites: Arc<Mutex<Vec<Site>>>,
    copyright_keywords: Arc<Vec<String>>,
    category_keywords: Arc<Vec<String>>,
    max_timeout: Duration,
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
            sites: Arc::new(Mutex::new(sites)),
            copyright_keywords: Arc::new(copyright_keywords),
            category_keywords: Arc::new(category_keywords),
            max_timeout: Duration::from_secs(10),
        }
    }

    pub fn get_sites(&self) -> Vec<Site> {
        self.sites.lock().unwrap().clone()
    }

    pub fn update_sites(&self, sites: Vec<Site>) {
        let mut s = self.sites.lock().unwrap();
        *s = sites;
    }

    pub async fn search(&self, keyword: &str, bypass_filter: bool) -> Result<SearchResult> {
        info!("开始搜索: {}", keyword);

        let sites = self.sites.lock().unwrap().clone();
        let enabled_sites: Vec<_> = sites.iter().filter(|s| s.enabled).collect();

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
            let timeout = self.max_timeout;

            let task = tokio::spawn(async move {
                tokio::time::timeout(
                    timeout,
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

    pub async fn get_detail(&self, source_key: &str, vod_id: &str) -> Result<VodItem> {
        info!("获取详情: {} - {}", source_key, vod_id);

        let sites = self.sites.lock().unwrap().clone();
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
