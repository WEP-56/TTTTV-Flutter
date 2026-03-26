use actix_web::{dev::ServerHandle, web, App, HttpRequest, HttpResponse, HttpServer, Responder};
use futures::TryStreamExt;
use reqwest::Client;
use serde::Deserialize;
use std::io::ErrorKind;
use std::net::TcpStream;
use std::sync::{Arc, Mutex as StdMutex};
use std::time::Duration;

#[derive(Default, Clone)]
pub struct StreamUrlStore {
    pub url: Arc<StdMutex<String>>,
    pub platform: Arc<StdMutex<String>>,
}

#[derive(Default)]
pub struct ProxyServerHandle(pub StdMutex<Option<ServerHandle>>);

#[derive(Deserialize)]
struct ImageQuery {
    url: String,
}

async fn image_proxy_handler(
    query: web::Query<ImageQuery>,
    client: web::Data<Client>,
) -> impl Responder {
    let url = query.url.clone();
    if url.is_empty() {
        return HttpResponse::BadRequest().body("Missing url query parameter");
    }

    let mut req = client
        .get(&url)
        .header(
            "User-Agent",
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
        )
        .header(
            "Accept",
            "image/avif,image/webp,image/apng,image/*;q=0.8,*/*;q=0.5",
        );

    if url.contains("hdslb.com") || url.contains("bilibili.com") {
        req = req
            .header("Referer", "https://live.bilibili.com/")
            .header("Origin", "https://live.bilibili.com");
    } else if url.contains("huya.com") {
        req = req
            .header("Referer", "https://www.huya.com/")
            .header("Origin", "https://www.huya.com");
    } else if url.contains("douyin") || url.contains("douyinpic.com") {
        req = req.header("Referer", "https://www.douyin.com/");
    } else if url.contains("douyu") {
        req = req.header("Referer", "https://www.douyu.com/");
    }

    match req.send().await {
        Ok(upstream_response) => {
            let content_type = upstream_response
                .headers()
                .get(reqwest::header::CONTENT_TYPE)
                .and_then(|v| v.to_str().ok())
                .unwrap_or("application/octet-stream")
                .to_string();

            if upstream_response.status().is_success() {
                match upstream_response.bytes().await {
                    Ok(bytes) => HttpResponse::Ok()
                        .content_type(content_type)
                        .insert_header(("Content-Length", bytes.len().to_string()))
                        .insert_header(("Cache-Control", "no-store"))
                        .body(bytes),
                    Err(e) => {
                        eprintln!("[proxy.rs image] Failed to read bytes: {}", e);
                        HttpResponse::InternalServerError()
                            .body(format!("Failed to read image bytes: {}", e))
                    }
                }
            } else {
                let status_from_reqwest = upstream_response.status();
                let error_text = upstream_response
                    .text()
                    .await
                    .unwrap_or_else(|e| format!("Failed to read error body: {}", e));
                eprintln!(
                    "[proxy.rs image] Upstream request to {} failed with status: {}. Body: {}",
                    url, status_from_reqwest, error_text
                );
                let actix_status_code =
                    actix_web::http::StatusCode::from_u16(status_from_reqwest.as_u16())
                        .unwrap_or(actix_web::http::StatusCode::INTERNAL_SERVER_ERROR);

                HttpResponse::build(actix_status_code).body(format!(
                    "Error fetching IMAGE from upstream: {}. Status: {}. Details: {}",
                    url, status_from_reqwest, error_text
                ))
            }
        }
        Err(e) => {
            eprintln!(
                "[proxy.rs image] Failed to send request to upstream {}: {}",
                url, e
            );
            HttpResponse::InternalServerError()
                .body(format!("Error connecting to upstream IMAGE {}: {}", url, e))
        }
    }
}

async fn flv_proxy_handler(
    _req: HttpRequest,
    stream_url_store: web::Data<StreamUrlStore>,
    client: web::Data<Client>,
) -> impl Responder {
    let url = stream_url_store.url.lock().unwrap().clone();
    let platform = stream_url_store.platform.lock().unwrap().clone();

    if url.is_empty() {
        return HttpResponse::NotFound().body("Stream URL is not set or empty.");
    }

    println!("[proxy.rs handler] Incoming FLV proxy request -> {} (platform: {})", url, platform);

    let mut req = client
        .get(&url)
        .header("Accept", "video/x-flv,application/octet-stream,*/*")
        .header("Connection", "keep-alive");

    // 根据平台添加必要的 headers
    match platform.as_str() {
        "huya" => {
            req = req
                .header("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36")
                .header("Referer", "https://www.huya.com/")
                .header("Origin", "https://www.huya.com");
        }
        "douyu" => {
            req = req
                .header("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36")
                .header("Referer", "https://www.douyu.com/");
        }
        "bilibili" => {
            req = req
                .header("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36")
                .header("Referer", "https://live.bilibili.com/");
        }
        _ => {
            req = req.header("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36");
        }
    }

    match req.send().await {
        Ok(upstream_response) => {
            let status = upstream_response.status();
            println!("[proxy.rs handler] Upstream response status: {}", status);

            if upstream_response.status().is_success() {
                let mut response_builder = HttpResponse::Ok();
                response_builder
                    .content_type("video/x-flv")
                    .insert_header(("Connection", "keep-alive"))
                    .insert_header(("Cache-Control", "no-store"))
                    .insert_header(("Accept-Ranges", "bytes"));

                let byte_stream = upstream_response.bytes_stream().map_err(|e| {
                    eprintln!(
                        "[proxy.rs handler] Error reading bytes from upstream: {}",
                        e
                    );
                    actix_web::error::ErrorInternalServerError(format!(
                        "Upstream stream error: {}",
                        e
                    ))
                });

                response_builder.streaming(byte_stream)
            } else {
                let status_from_reqwest = upstream_response.status();
                let error_text = upstream_response
                    .text()
                    .await
                    .unwrap_or_else(|e| format!("Failed to read error body: {}", e));
                eprintln!(
                    "[proxy.rs handler] Upstream request to {} failed with status: {}. Body: {}",
                    url, status_from_reqwest, error_text
                );
                let actix_status_code =
                    actix_web::http::StatusCode::from_u16(status_from_reqwest.as_u16())
                        .unwrap_or(actix_web::http::StatusCode::INTERNAL_SERVER_ERROR);

                HttpResponse::build(actix_status_code).body(format!(
                    "Error fetching FLV stream from upstream: {}. Status: {}. Details: {}",
                    url, status_from_reqwest, error_text
                ))
            }
        }
        Err(e) => {
            eprintln!(
                "[proxy.rs handler] Failed to send request to upstream {}: {}",
                url, e
            );
            HttpResponse::InternalServerError().body(format!(
                "Error connecting to upstream FLV stream {}: {}",
                url, e
            ))
        }
    }
}

pub async fn start_proxy(
    server_handle_state: Arc<StdMutex<Option<ServerHandle>>>,
    stream_url_store: StreamUrlStore,
) -> Result<String, String> {
    let port = 34719u16;
    let current_stream_url = stream_url_store.url.lock().unwrap().clone();

    if current_stream_url.is_empty() {
        return Err("Stream URL is not set in store. Cannot start proxy.".to_string());
    }

    let stream_url_data_for_actix = web::Data::new(stream_url_store.clone());

    let existing_handle_to_stop = { server_handle_state.lock().unwrap().take() };
    if let Some(existing_handle) = existing_handle_to_stop {
        existing_handle.stop(false).await;
    }

    let server = match HttpServer::new(move || {
        let app_data_stream_url = stream_url_data_for_actix.clone();
        let app_data_reqwest_client = web::Data::new(
            Client::builder()
                .no_proxy()
                .http1_only()
                .no_brotli()
                .no_deflate()
                .pool_idle_timeout(None)
                .pool_max_idle_per_host(4)
                .tcp_keepalive(Duration::from_secs(60))
                .timeout(Duration::from_secs(7200))
                .build()
                .expect("failed to build client"),
        );
        App::new()
            .app_data(app_data_stream_url)
            .app_data(app_data_reqwest_client)
            .wrap(actix_cors::Cors::permissive())
            .route("/live.flv", web::get().to(flv_proxy_handler))
            .route("/image", web::get().to(image_proxy_handler))
    })
    .keep_alive(Duration::from_secs(120))
    .bind(("127.0.0.1", port))
    {
        Ok(srv) => srv,
        Err(e) => {
            let err_msg = format!("[proxy.rs] Failed to bind server to port {}: {}", port, e);
            eprintln!("{}", err_msg);
            return Err(err_msg);
        }
    }
    .run();

    let server_handle_for_state = server.handle();
    *server_handle_state.lock().unwrap() = Some(server_handle_for_state);

    tokio::spawn(async move {
        if let Err(e) = server.await {
            eprintln!("[proxy.rs] Proxy server run error: {}", e);
        } else {
            println!("[proxy.rs] Proxy server on port {} shut down.", port);
        }
    });

    let proxy_url = format!("http://127.0.0.1:{}/live.flv", port);
    Ok(proxy_url)
}

pub async fn start_static_proxy_server(
    stream_url_store: StreamUrlStore,
) -> Result<String, String> {
    let port: u16 = 34721;

    if TcpStream::connect(("127.0.0.1", port)).is_ok() {
        return Ok(format!("http://127.0.0.1:{}", port));
    }

    let stream_url_data_for_actix = web::Data::new(stream_url_store);

    let server = match HttpServer::new(move || {
        let app_data_stream_url = stream_url_data_for_actix.clone();
        let app_data_reqwest_client = web::Data::new(
            Client::builder()
                .no_proxy()
                .http1_only()
                .no_brotli()
                .no_deflate()
                .pool_idle_timeout(None)
                .pool_max_idle_per_host(4)
                .tcp_keepalive(Duration::from_secs(60))
                .timeout(Duration::from_secs(7200))
                .build()
                .expect("failed to build client"),
        );
        App::new()
            .app_data(app_data_stream_url)
            .app_data(app_data_reqwest_client)
            .wrap(actix_cors::Cors::permissive())
            .route("/live.flv", web::get().to(flv_proxy_handler))
            .route("/image", web::get().to(image_proxy_handler))
    })
    .keep_alive(Duration::from_secs(120))
    .bind(("127.0.0.1", port))
    {
        Ok(srv) => srv,
        Err(e) => {
            if e.kind() == ErrorKind::AddrInUse {
                eprintln!(
                    "[proxy.rs] Port {} already in use; assuming static proxy running.",
                    port
                );
                return Ok(format!("http://127.0.0.1:{}", port));
            }
            let err_msg = format!("[proxy.rs] Failed to bind server to port {}: {}", port, e);
            eprintln!("{}", err_msg);
            return Err(err_msg);
        }
    }
    .run();

    tokio::spawn(async move {
        if let Err(e) = server.await {
            eprintln!("[proxy.rs] Proxy server run error: {}", e);
        } else {
            println!("[proxy.rs] Proxy server on port {} shut down.", port);
        }
    });

    Ok(format!("http://127.0.0.1:{}", port))
}

pub async fn stop_proxy(server_handle_state: Arc<StdMutex<Option<ServerHandle>>>) -> Result<(), String> {
    let handle_to_stop = { server_handle_state.lock().unwrap().take() };

    if let Some(handle) = handle_to_stop {
        handle.stop(false).await;
        println!("[proxy.rs] stop_proxy: Initiated non-graceful shutdown.");
    } else {
        println!("[proxy.rs] stop_proxy command: No proxy server was running or handle already taken.");
    }
    Ok(())
}
