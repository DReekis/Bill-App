# 🚀 100% Free Tier AWS Deployment Guide for Billket Cloud

This guide provides step-by-step instructions to deploy the Billket backend to **Amazon Web Services (AWS) 100% FREE** using the **AWS 12-Month Free Tier** (750 hours/month of Amazon EC2 `t2.micro` or `t3.micro`).

---

## 🎯 Why This Path is 100% Free

| Service | Free Tier Allowance | How Billket Cloud Uses It | Cost |
| :--- | :--- | :--- | :--- |
| **Amazon EC2** | **750 hours/month** of `t2.micro` or `t3.micro` | Runs 24/7 all month long (750 hrs = 31.25 days) hosting Fastify & PostgreSQL in Docker | **$0.00 / mo** |
| **EBS Storage** | **30 GB** free gp3 storage | 20 GB allocated to OS + Docker containers + Database | **$0.00 / mo** |
| **Data Transfer** | **100 GB** data transfer out / month | On-demand JSON sync uses minimal KB bandwidth | **$0.00 / mo** |
| **Amazon S3** | **5 GB** standard storage | Encrypted database snapshots and CA audit archives | **$0.00 / mo** |
| **Total Bill** | | | **$0.00 / mo** |

> [!NOTE]
> Unlike AWS App Runner (which charges for idle container memory), **Amazon EC2 `t2.micro` / `t3.micro` is 100% covered by the AWS Free Tier**. By running both the Fastify API and PostgreSQL inside Docker on the same EC2 instance, you get zero database file locking, full multi-user concurrency, and zero monthly server bills!

---

## 🏗️ System Architecture on Free Tier EC2

```mermaid
flowchart TD
    subgraph Client_Layer [Client Applications]
        Android[📱 Android Phones / Tablets<br/>Package: com.pricepilot.bill]
        iOS[🍏 iPhones / iPads]
        Desktop[💻 Windows POS Desktop]
        Web[🌐 Web Browser / Portal]
    end

    subgraph AWS_EC2 [AWS EC2 Free Tier: t2.micro or t3.micro<br/>750 Hours Free / Month - Region: ap-south-1 Mumbai]
        subgraph Docker_Compose [Docker Compose Environment]
            API[⚡ Fastify REST API Container<br/>Port: 80 & 4000<br/>JWT Auth + Google idToken Verification]
            PG[(🐘 PostgreSQL 16 Alpine Container<br/>Internal Port: 5432<br/>Persistent Docker Volume: postgres_data)]
        end
        Swap[1.5 GB Swap File<br/>Prevents OOM on 1GB RAM]
    end

    Client_Layer ==>|HTTP / HTTPS REST on Demand| API
    API <-->|High-Speed Unix/Docker Socket| PG
    Docker_Compose --- Swap
```

---

## 📋 Prerequisites

1. An **AWS Account** ([aws.amazon.com](https://aws.amazon.com)).
2. Your Google OAuth credentials (from Google Cloud Console):
   - **Google Client Secret**: Keep in your private `backend/.env`
   - **Google Web/Server Client ID**: `your_web_server_client_id.apps.googleusercontent.com`
   - **Google Android Client ID**: `your_android_client_id.apps.googleusercontent.com`
   - **Google iOS Client ID**: `your_ios_client_id.apps.googleusercontent.com`

---

## 🛠️ Step 1: Launch an AWS EC2 Free Tier Instance (3 minutes)

1. Log into your [AWS Management Console](https://console.aws.amazon.com/).
2. In the top-right region selector, choose **Asia Pacific (Mumbai) `ap-south-1`** (fastest response times for Indian merchants).
3. In the search bar, type **EC2** and click **Launch instance**.
4. Configure your instance:
   - **Name**: `billket-cloud-server`
   - **Application and OS Images (AMI)**: **Ubuntu Server 24.04 LTS** (Make sure it says *"Free tier eligible"*).
   - **Instance type**: **`t2.micro`** or **`t3.micro`** (1 vCPU, 1 GiB Memory, *"Free tier eligible"*).
   - **Key pair (login)**:
     - Click **Create new key pair**.
     - Name: `billket-key`, Type: `RSA`, Format: `.pem`.
     - Click **Create key pair** and download the file.
   - **Network settings**:
     - Check: **Allow SSH traffic from Anywhere** (0.0.0.0/0).
     - Check: **Allow HTTP traffic from the internet** (Port 80).
     - Check: **Allow HTTPS traffic from the internet** (Port 443).
   - **Configure storage**:
     - Change from 8 GiB to **20 GiB** `gp3` (AWS Free Tier allows up to 30 GiB free!).
5. Click **Launch instance**. Your instance will be ready in under 60 seconds!

---

## 🔑 Step 2: Open Custom Port 4000 in AWS Security Group

1. In the EC2 console, go to **Instances** -> Click on your running instance.
2. Click the **Security** tab at the bottom -> Click the link under **Security groups** (e.g. `launch-wizard-1`).
3. Click **Edit inbound rules** -> Click **Add rule**:
   - **Type**: Custom TCP
   - **Port range**: `4000`
   - **Source**: `Anywhere-IPv4` (`0.0.0.0/0`)
   - **Description**: `Billket API direct port`
4. Click **Save rules**.

---

## ⚡ Step 3: Connect to EC2 and Run 1-Click Setup (3 minutes)

1. In the EC2 console, select your instance and click the **Connect** button at the top.
2. Select **EC2 Instance Connect** -> Click **Connect** (Opens a terminal right inside your web browser — no software needed!).
   *(Alternatively, connect via SSH using `ssh -i billket-key.pem ubuntu@<YOUR-EC2-PUBLIC-IP>`)*.

3. Once connected, run the following commands:
   ```bash
   # 1. Clone your Bill-App repository
   git clone https://github.com/<your-username>/Bill-App.git
   cd Bill-App

   # 2. Run the automated 1-click Free Tier setup script
   chmod +x backend/scripts/ec2-setup.sh
   ./backend/scripts/ec2-setup.sh
   ```
   *This script automatically updates Ubuntu, creates a 1.5 GB swap file (preventing low memory issues on t2.micro), and installs the official Docker Engine and Docker Compose.*

4. Configure your production environment variables:
   ```bash
   nano backend/.env
   ```
   Paste the following:
   ```env
   PORT=4000
   NODE_ENV=production
   JWT_SECRET=billket_jwt_secret_production_ready_secure_2026
   DATABASE_URL=postgresql://billket_user:billket_secure_password_2026@postgres:5432/billket_db?schema=public

   # Executive Admin Dashboard Credentials (SECURE THESE - REQUIRED)
    ADMIN_EMAIL=admin@pricepilot.in
    ADMIN_PASSWORD=SetYourStrongPasswordHere_2026!

   # Google OAuth Credentials (paste from your secure notes)
   GOOGLE_CLIENT_SECRET=your_google_client_secret_here
   GOOGLE_CLIENT_ID=your_web_server_client_id.apps.googleusercontent.com
   GOOGLE_ANDROID_CLIENT_ID=your_android_client_id.apps.googleusercontent.com
   GOOGLE_IOS_CLIENT_ID=your_ios_client_id.apps.googleusercontent.com
   ```
   Press `Ctrl + O`, then `Enter` to save, and `Ctrl + X` to exit.

5. Start the complete Billket Cloud Stack:
   ```bash
   sudo docker compose up -d --build
   ```

6. Verify containers are healthy:
   ```bash
   sudo docker compose ps
   ```
   You will see both `billket-postgres` and `billket-api` running:
   ```
   NAME               IMAGE                    COMMAND                  SERVICE    STATUS
   billket-api        bill-app-api             "dumb-init -- ./dock…"   api        running (healthy)
   billket-postgres   postgres:16-alpine       "docker-entrypoint.s…"   postgres   running (healthy)
   ```

---

## 🔍 Step 4: Verify Your Server Live in Browser

Find your **Public IPv4 address** on your EC2 Instance details page (e.g. `13.233.54.120`).

1. **Test Health Endpoint**:
   Open in your browser:
   ```
   http://<YOUR-EC2-PUBLIC-IP>/health
   ```
   Expected response:
   ```json
   {"ok": true, "service": "pricepilot-bill-backend"}
   ```

2. **Access Master Tenant Admin Dashboard**:
   Open in your browser:
   ```
   http://<YOUR-EC2-PUBLIC-IP>/admin
   ```
   You can view tenant businesses, manage users, and inspect real-time sync queues.

---

## 📱 Step 5: Connect the Flutter App to Your AWS Cloud

You can point the mobile app to your live AWS server in two ways:

### Method A: In-App Configuration (Immediate, No Rebuild Needed!)
1. Open the Billket app on your phone.
2. Go to **More** -> **Cloud Backup & Restore** (or **Settings**).
3. In **Cloud Server Endpoint**, enter:
   ```
   http://<YOUR-EC2-PUBLIC-IP>
   ```
4. Tap **Save & Test Connection**. The app will connect, and your sync badge will turn green!

### Method B: Production Release Build (for Play Store)
Build the signed APK with compile-time environment variables:
```powershell
flutter build apk --release `
  --dart-define=API_BASE_URL=http://<YOUR-EC2-PUBLIC-IP> `
  --dart-define=GOOGLE_SERVER_CLIENT_ID=your_web_server_client_id.apps.googleusercontent.com `
  --dart-define=GOOGLE_ANDROID_CLIENT_ID=your_android_client_id.apps.googleusercontent.com
```

---

## 🔒 Optional: Add Free HTTPS Domain with Caddy or DuckDNS

If you want a free domain with automatic SSL (`https://`):
1. Get a free domain at [duckdns.org](https://www.duckdns.org) (e.g. `billket-api.duckdns.org`) pointing to your EC2 Public IP.
2. Run Caddy in one command on your EC2 instance:
   ```bash
   sudo apt-get install -y debian-keyring debian-archive-keyring apt-transport-https curl
   curl -1sLF 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | sudo gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
   curl -1sLF 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | sudo tee /etc/apt/sources.list.d/caddy-stable.list
   sudo apt-get update
   sudo apt-get install caddy
   ```
3. In `/etc/caddy/Caddyfile`:
   ```caddy
   billket-api.duckdns.org {
       reverse_proxy localhost:4000
   }
   ```
4. Run `sudo systemctl restart caddy`. Caddy automatically acquires a free Let's Encrypt SSL certificate!

---

## 🛠️ Maintenance & Useful Commands

| Task | Command |
| :--- | :--- |
| **View Live API Logs** | `sudo docker compose logs -f api` |
| **View Database Logs** | `sudo docker compose logs -f postgres` |
| **Restart Server** | `sudo docker compose restart` |
| **Update with New Code** | `git pull && sudo docker compose up -d --build` |
| **Inspect Running Containers** | `sudo docker compose ps` |
