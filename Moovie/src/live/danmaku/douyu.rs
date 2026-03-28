use axum::extract::ws::{Message as AxumMessage, WebSocket};
use futures::{SinkExt, StreamExt};
use serde_json::{Map, Value};
use std::time::Duration;
use tokio_tungstenite::connect_async;
use tokio_tungstenite::tungstenite::{Message as WsMessage, client::IntoClientRequest};

use crate::live::models::{LiveMessage, LiveMessageColor, LiveMessageType};
use crate::utils::error::MoovieError;

pub async fn bridge(room_id: String, socket: WebSocket) -> Result<(), MoovieError> {
    if room_id.trim().is_empty() {
        return Err(MoovieError::InvalidParameter(
            "room_id 不能为空".to_string(),
        ));
    }

    let ws_url = "wss://danmuproxy.douyu.com:8506";
    let request = ws_url
        .into_client_request()
        .map_err(|e| MoovieError::InvalidParameter(format!("ws url 解析失败: {}", e)))?;
    let (upstream, _resp) = connect_async(request)
        .await
        .map_err(|e| MoovieError::Unknown(e.to_string()))?;
    let (mut up_tx, mut up_rx) = upstream.split();

    let (mut client_tx, mut client_rx) = socket.split();

    // login + join group
    up_tx
        .send(WsMessage::Binary(serialize_douyu(&format!(
            "type@=loginreq/roomid@={}/",
            room_id
        ))))
        .await
        .map_err(|e| MoovieError::Unknown(e.to_string()))?;
    up_tx
        .send(WsMessage::Binary(serialize_douyu(&format!(
            "type@=joingroup/rid@={}/gid@=-9999/",
            room_id
        ))))
        .await
        .map_err(|e| MoovieError::Unknown(e.to_string()))?;

    let mut heartbeat = tokio::time::interval(Duration::from_secs(45));

    loop {
        tokio::select! {
            _ = heartbeat.tick() => {
                let hb = serialize_douyu("type@=mrkl/");
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
                    let packets = parse_packets(&data);
                    for pkt in packets {
                        if let Some(live_msg) = parse_douyu_message(&pkt) {
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
            }
            client = client_rx.next() => {
                if client.is_none() {
                    break;
                }
            }
        }
    }

    Ok(())
}

fn serialize_douyu(body: &str) -> Vec<u8> {
    // Protocol ported from dart_simple_live: body is UTF-8, packet_len = body_len + 9.
    const PACK_TYPE: u16 = 689;
    const ENCRYPTED: u8 = 0;
    const RESERVED: u8 = 0;

    let body_bytes = body.as_bytes();
    let packet_len = (body_bytes.len() + 9) as u32;

    let mut out = Vec::with_capacity(body_bytes.len() + 13);
    out.extend_from_slice(&packet_len.to_le_bytes());
    out.extend_from_slice(&packet_len.to_le_bytes());
    out.extend_from_slice(&PACK_TYPE.to_le_bytes());
    out.push(ENCRYPTED);
    out.push(RESERVED);
    out.extend_from_slice(body_bytes);
    out.push(0);
    out
}

fn parse_packets(mut data: &[u8]) -> Vec<String> {
    let mut out = Vec::new();
    while data.len() >= 4 {
        let packet_len = u32::from_le_bytes([data[0], data[1], data[2], data[3]]) as usize;
        let total_len = packet_len + 4;
        if packet_len < 9 || total_len > data.len() {
            break;
        }
        let pkt = &data[..total_len];
        if let Some(text) = parse_one_packet(pkt) {
            out.push(text);
        }
        data = &data[total_len..];
    }
    out
}

fn parse_one_packet(pkt: &[u8]) -> Option<String> {
    if pkt.len() < 13 {
        return None;
    }
    let packet_len = u32::from_le_bytes([pkt[0], pkt[1], pkt[2], pkt[3]]) as usize;
    if packet_len + 4 != pkt.len() {
        return None;
    }
    let body_len = packet_len.checked_sub(9)?;
    let body_start: usize = 12;
    let body_end = body_start.checked_add(body_len)?;
    if body_end + 1 > pkt.len() {
        return None;
    }
    let body = &pkt[body_start..body_end];
    String::from_utf8(body.to_vec()).ok()
}

fn parse_douyu_message(text: &str) -> Option<LiveMessage> {
    let json = stt_to_json(text);
    let Value::Object(obj) = json else {
        return None;
    };
    let msg_type = obj.get("type").and_then(|v| v.as_str()).unwrap_or("");
    if msg_type != "chatmsg" {
        return None;
    }
    // Filter "阴间弹幕" (no dms field)
    if !obj.contains_key("dms") {
        return None;
    }

    let user_name = obj
        .get("nn")
        .and_then(|v| v.as_str())
        .unwrap_or("")
        .to_string();
    let message = obj
        .get("txt")
        .and_then(|v| v.as_str())
        .unwrap_or("")
        .to_string();
    let col = obj
        .get("col")
        .and_then(|v| {
            v.as_str()
                .and_then(|s| s.parse::<i64>().ok())
                .or_else(|| v.as_i64())
        })
        .unwrap_or(0);

    Some(LiveMessage {
        kind: LiveMessageType::Chat,
        user_name,
        message,
        color: douyu_color(col as i64),
        data: None,
    })
}

fn stt_to_json(input: &str) -> Value {
    if input.contains("//") {
        let arr: Vec<Value> = input
            .split("//")
            .filter(|s| !s.is_empty())
            .map(stt_to_json)
            .collect();
        return Value::Array(arr);
    }

    if input.contains("@=") {
        let mut map = Map::new();
        for field in input.split('/') {
            if field.is_empty() {
                continue;
            }
            let mut parts = field.splitn(2, "@=");
            let key = parts.next().unwrap_or("").to_string();
            let val_raw = parts.next().unwrap_or("");
            let val_raw = unescape_stt(val_raw);
            map.insert(key, stt_to_json(&val_raw));
        }
        return Value::Object(map);
    }

    if input.contains("@A=") {
        return stt_to_json(&unescape_stt(input));
    }

    Value::String(unescape_stt(input))
}

fn unescape_stt(input: &str) -> String {
    input.replace("@S", "/").replace("@A", "@")
}

fn douyu_color(t: i64) -> LiveMessageColor {
    match t {
        1 => LiveMessageColor { r: 255, g: 0, b: 0 },
        2 => LiveMessageColor {
            r: 30,
            g: 135,
            b: 240,
        },
        3 => LiveMessageColor {
            r: 122,
            g: 200,
            b: 75,
        },
        4 => LiveMessageColor {
            r: 255,
            g: 127,
            b: 0,
        },
        5 => LiveMessageColor {
            r: 155,
            g: 57,
            b: 244,
        },
        6 => LiveMessageColor {
            r: 255,
            g: 105,
            b: 180,
        },
        _ => LiveMessageColor {
            r: 255,
            g: 255,
            b: 255,
        },
    }
}
