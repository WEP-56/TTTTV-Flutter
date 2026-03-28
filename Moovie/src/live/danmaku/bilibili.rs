use axum::extract::ws::{Message as AxumMessage, WebSocket};
use brotli::Decompressor;
use flate2::read::ZlibDecoder;
use futures::{SinkExt, StreamExt};
use serde_json::Value;
use std::io::Read;
use std::time::Duration;
use tokio_tungstenite::connect_async;
use tokio_tungstenite::tungstenite::{Message as WsMessage, client::IntoClientRequest};

use crate::live::models::{LiveMessage, LiveMessageColor, LiveMessageType};
use crate::live::providers::bilibili::BiliBiliProvider;
use crate::utils::error::MoovieError;

pub async fn bridge(
    http_client: reqwest::Client,
    cookie: String,
    room_id: String,
    socket: WebSocket,
) -> Result<(), MoovieError> {
    let provider = BiliBiliProvider::new(http_client.clone(), cookie);
    let info = provider.get_danmaku_info(&room_id).await?;
    if info.token.is_empty() {
        return Err(MoovieError::ConfigError(
            "Bilibili 弹幕 token 获取失败".to_string(),
        ));
    }

    let ws_url = format!("wss://{}/sub", info.server_host);
    let mut request = ws_url
        .into_client_request()
        .map_err(|e| MoovieError::InvalidParameter(format!("ws url 解析失败: {}", e)))?;
    if !info.cookie.trim().is_empty() {
        request.headers_mut().insert(
            "cookie",
            info.cookie
                .parse()
                .map_err(|_| MoovieError::InvalidParameter("cookie header 无效".to_string()))?,
        );
    }

    let (upstream, _resp) = connect_async(request)
        .await
        .map_err(|e| MoovieError::Unknown(e.to_string()))?;
    let (mut up_tx, mut up_rx) = upstream.split();

    let (mut client_tx, mut client_rx) = socket.split();

    // join room
    let join_json = serde_json::json!({
        "uid": info.uid,
        "roomid": info.room_id,
        "protover": 3,
        "buvid": info.buvid,
        "platform": "web",
        "type": 2,
        "key": info.token,
    })
    .to_string();
    let join_packet = encode_packet(join_json.as_bytes(), 7, 0);
    up_tx
        .send(WsMessage::Binary(join_packet))
        .await
        .map_err(|e| MoovieError::Unknown(e.to_string()))?;

    let mut heartbeat = tokio::time::interval(Duration::from_secs(60));

    loop {
        tokio::select! {
            _ = heartbeat.tick() => {
                let hb = encode_packet(&[], 2, 0);
                if up_tx.send(WsMessage::Binary(hb)).await.is_err() {
                    break;
                }
            }
            msg = up_rx.next() => {
                let Some(msg) = msg else { break; };
                let msg = match msg {
                    Ok(m) => m,
                    Err(_) => break,
                };
                if let WsMessage::Binary(data) = msg {
                    let messages = decode_bilibili_message(&data);
                    for live_msg in messages {
                        let text = match serde_json::to_string(&live_msg) {
                            Ok(t) => t,
                            Err(_) => continue,
                        };
                        if client_tx.send(AxumMessage::Text(text)).await.is_err() {
                            return Ok(());
                        }
                    }
                }
            }
            client = client_rx.next() => {
                // client closed or ignored
                if client.is_none() {
                    break;
                }
            }
        }
    }

    Ok(())
}

fn encode_packet(body: &[u8], operation: u32, protocol_version: u16) -> Vec<u8> {
    let header_len: u16 = 16;
    let packet_len = header_len as usize + body.len();
    let mut buf = Vec::with_capacity(packet_len);

    buf.extend_from_slice(&(packet_len as u32).to_be_bytes()); // packet length
    buf.extend_from_slice(&header_len.to_be_bytes()); // header length
    buf.extend_from_slice(&protocol_version.to_be_bytes()); // protocol version
    buf.extend_from_slice(&operation.to_be_bytes()); // operation
    buf.extend_from_slice(&1u32.to_be_bytes()); // sequence
    buf.extend_from_slice(body);

    buf
}

fn decode_bilibili_message(data: &[u8]) -> Vec<LiveMessage> {
    let mut all = Vec::new();
    for pkt in parse_packets(data) {
        match pkt.operation {
            3 => {
                if pkt.body.len() >= 4 {
                    let online =
                        i32::from_be_bytes([pkt.body[0], pkt.body[1], pkt.body[2], pkt.body[3]])
                            as i64;
                    all.push(LiveMessage {
                        kind: LiveMessageType::Online,
                        user_name: "".to_string(),
                        message: "".to_string(),
                        color: LiveMessageColor {
                            r: 255,
                            g: 255,
                            b: 255,
                        },
                        data: Some(serde_json::json!(online)),
                    });
                }
            }
            5 => {
                let mut bodies: Vec<Vec<u8>> = vec![pkt.body];
                if pkt.protocol_version == 2 {
                    bodies = bodies
                        .into_iter()
                        .filter_map(|b| zlib_decompress(&b).ok())
                        .collect();
                } else if pkt.protocol_version == 3 {
                    bodies = bodies
                        .into_iter()
                        .filter_map(|b| brotli_decompress(&b).ok())
                        .collect();
                }

                for body in bodies {
                    // sometimes decompressed body is itself a packet stream
                    let nested = parse_packets(&body);
                    if !nested.is_empty() && nested.iter().all(|p| p.packet_len >= 16) {
                        for n in nested {
                            all.extend(decode_bilibili_message(&encode_packet(
                                &n.body,
                                n.operation,
                                n.protocol_version,
                            )));
                        }
                        continue;
                    }

                    all.extend(parse_json_messages(&body));
                }
            }
            _ => {}
        }
    }
    all
}

#[derive(Debug, Clone)]
struct Packet {
    packet_len: usize,
    header_len: usize,
    protocol_version: u16,
    operation: u32,
    body: Vec<u8>,
}

fn parse_packets(mut data: &[u8]) -> Vec<Packet> {
    let mut packets = Vec::new();
    while data.len() >= 16 {
        let packet_len = u32::from_be_bytes([data[0], data[1], data[2], data[3]]) as usize;
        if packet_len < 16 || packet_len > data.len() {
            break;
        }
        let header_len = u16::from_be_bytes([data[4], data[5]]) as usize;
        if header_len < 16 || header_len > packet_len {
            break;
        }
        let protocol_version = u16::from_be_bytes([data[6], data[7]]);
        let operation = u32::from_be_bytes([data[8], data[9], data[10], data[11]]);
        let body = data[header_len..packet_len].to_vec();

        packets.push(Packet {
            packet_len,
            header_len,
            protocol_version,
            operation,
            body,
        });

        data = &data[packet_len..];
    }
    packets
}

fn zlib_decompress(input: &[u8]) -> std::io::Result<Vec<u8>> {
    let mut decoder = ZlibDecoder::new(input);
    let mut out = Vec::new();
    decoder.read_to_end(&mut out)?;
    Ok(out)
}

fn brotli_decompress(input: &[u8]) -> std::io::Result<Vec<u8>> {
    let mut decompressor = Decompressor::new(input, 4096);
    let mut out = Vec::new();
    decompressor.read_to_end(&mut out)?;
    Ok(out)
}

fn parse_json_messages(bytes: &[u8]) -> Vec<LiveMessage> {
    let text = String::from_utf8_lossy(bytes);
    let mut out = Vec::new();

    for part in text.split(|c: char| (c as u32) < 0x20) {
        let part = part.trim();
        if part.len() < 2 || !part.starts_with('{') {
            continue;
        }
        if let Ok(obj) = serde_json::from_str::<Value>(part) {
            if let Some(cmd) = obj.get("cmd").and_then(|v| v.as_str()) {
                if cmd.contains("DANMU_MSG") {
                    if let Some(info) = obj.get("info").and_then(|v| v.as_array()) {
                        let message = info
                            .get(1)
                            .and_then(|v| v.as_str())
                            .unwrap_or("")
                            .to_string();
                        let color_num = info
                            .get(0)
                            .and_then(|v| v.as_array())
                            .and_then(|arr| arr.get(3))
                            .and_then(|v| v.as_i64())
                            .unwrap_or(0);
                        let user_name = info
                            .get(2)
                            .and_then(|v| v.as_array())
                            .and_then(|arr| arr.get(1))
                            .and_then(|v| v.as_str())
                            .unwrap_or("")
                            .to_string();

                        out.push(LiveMessage {
                            kind: LiveMessageType::Chat,
                            user_name,
                            message,
                            color: color_number_to_rgb(color_num),
                            data: None,
                        });
                    }
                } else if cmd == "SUPER_CHAT_MESSAGE" {
                    if let Some(data) = obj.get("data") {
                        out.push(LiveMessage {
                            kind: LiveMessageType::SuperChat,
                            user_name: "SUPER_CHAT".to_string(),
                            message: "SUPER_CHAT".to_string(),
                            color: LiveMessageColor {
                                r: 255,
                                g: 255,
                                b: 255,
                            },
                            data: Some(data.clone()),
                        });
                    }
                }
            }
        }
    }

    out
}

fn color_number_to_rgb(color: i64) -> LiveMessageColor {
    if color <= 0 {
        return LiveMessageColor {
            r: 255,
            g: 255,
            b: 255,
        };
    }
    let mut hex = format!("{:x}", color as u64);
    if hex.len() == 4 {
        hex = format!("00{}", hex);
    }
    if hex.len() == 8 {
        hex = hex.chars().skip(2).collect();
    }
    if hex.len() != 6 {
        return LiveMessageColor {
            r: 255,
            g: 255,
            b: 255,
        };
    }
    let r = u8::from_str_radix(&hex[0..2], 16).unwrap_or(255);
    let g = u8::from_str_radix(&hex[2..4], 16).unwrap_or(255);
    let b = u8::from_str_radix(&hex[4..6], 16).unwrap_or(255);
    LiveMessageColor { r, g, b }
}
