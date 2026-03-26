use moovie::{LocalServerOptions, init_tracing, start_local_server};

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    init_tracing();
    start_local_server(LocalServerOptions::default()).await
}
