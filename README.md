```
                                ██████╗ ██╗   ██╗██████╗ ██████╗
                                ██╔══██╗██║   ██║██╔══██╗██╔══██╗                            
                                ██████╔╝██║   ██║██████╔╝██████╔╝                            
                                ██╔═══╝ ██║   ██║██╔══██╗██╔══██╗                            
                                ██║     ╚██████╔╝██║  ██║██║  ██║                            
                                ╚═╝      ╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═╝                            
                                                             
                   ███╗   ███╗███████╗████████╗██╗  ██╗███████╗██╗   ██╗███████╗
                   ████╗ ████║██╔════╝╚══██╔══╝██║  ██║██╔════╝██║   ██║██╔════╝
                   ██╔████╔██║█████╗     ██║   ███████║█████╗  ██║   ██║███████╗
                   ██║╚██╔╝██║██╔══╝     ██║   ██╔══██║██╔══╝  ██║   ██║╚════██║
                   ██║ ╚═╝ ██║███████╗   ██║   ██║  ██║███████╗╚██████╔╝███████║
                   ╚═╝     ╚═╝╚══════╝   ╚═╝   ╚═╝  ╚═╝╚══════╝ ╚═════╝ ╚══════╝
                                          
                                 ;,_            ,
                                _uP~"b          d"u,
                               dP'   "b       ,d"  "o
                              d"    , `b     d"'    "b
                             l] [    " `l,  d"       lb
                             Ol ?     "  "b`"=uoqo,_  "l
                           ,dBb "b        "b,    `"~~TObup,_
                         ,d" (db.`"         ""     "tbc,_ `~"Yuu,_
                       .d" l`T'  '=                      ~     `""Yu,
                     ,dO` gP,                           `u,   b,_  "b7
                    d?' ,d" l,                           `"b,_ `~b  "1
                  ,8i' dl   `l                 ,ggQOV",dbgq,._"  `l  lb
                 .df' (O,    "             ,ggQY"~  , @@@@@d"bd~  `b "1
                .df'   `"           -=@QgpOY""     (b  @@@@P db    `Lp"b,
               .d(                  _               "ko "=d_,Q`  ,_  "  "b,
               Ql         .         `"qo,._          "tQo,_`""bo ;tb,    `"b,
               qQ         |L           ~"QQQgggc,_.,dObc,opooO  `"~~";.   __,7,
               qp         t\io,_           `~"TOOggQV""""        _,dg,_ =PIQHib.
               `qp        `Q["tQQQo,_                          ,pl{QOP"'   7AFR`
                 `         `tb  '""tQQQg,_             p" "b   `       .;-.`Vl'
                            "Yb      `"tQOOo,__    _,edb    ` .__   /`/'|  |b;=;.__
                                          `"tQQQOOOOP""`"\QV;qQObob"`-._`\_~~-._
                                               """"    ._        /   | |oP"\_   ~\ ~\_~\
                                                       `~"\ic,qggddOOP"|  |  ~\   `\~-._
                                                         ,qP`"""|"   | `\ `;   `\   `\
                                              _        _,p"     |    |   `\`;    |    |
                                              "boo,._dP"       `\_  `\    `\|   `\   ;
                                                `"7tY~'            `\  `\    `|_   |
                                                                     `~\  |
```
A monitoring solution for Hyperliquid nodes using Prometheus, Grafana and [hyperliquid-exporter](https://github.com/validaoxyz/hyperliquid-exporter).

## Features

- Custom Prometheus exporter for Hyperliquid nodes
- Pre-configured Grafana dashboards
- Dockerized setup for ease of deployment

## Prerequisites

Ensure you have Docker and Docker Compose installed:

```bash
sudo apt install -y docker docker-compose
```

## Installation

This setup is meant to run on the same machine as your HL node since [hyperliquid-exporter](https://github.com/validaoxyz/hyperliquid-exporter) relies on log file scraping to generate metrics for prometheus.


### 1. Clone the repository

```bash
git clone https://github.com/validaoxyz/purrmetheus.git
cd purrmetheus
```

### 2. **Set up environment variables:**

Copy `.env.sample` to `.env` and fill in the required values

```bash
cp .env.sample .env
```

### 3. Generate required files + build and start the containers
```bash
bash generate-config.sh
cd docker
docker-compose up -d
```

### 4. **Access the services**:

   Grafana will be available on port `3000`.
   To access your dashboard:
     - Ensure your firewall allows port `3000`
     - Visit `http://<your-ip>:3000` and log in using credentials from your `.env` file.


## Configuration

- **Grafana Dashboards**: Located in [grafana/dashboards/](grafana/dashboards).
- **Prometheus Configuration**: Files located in [prometheus/](prometheus/).
- **Exporter Code**: [validaoxyz/hyperliquid-exporter](https://github.com/validaoxyz/hyperliquid-exporter).

## Docs
Docs on metrics can be found under [docs/](https://github.com/validaoxyz/purrmetheus/docs/metrics)

## Contributing
Contributions are greatly appreciated. Please submit a PR or open an issue on GitHub.
