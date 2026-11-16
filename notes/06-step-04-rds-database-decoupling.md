# 🗄️ Step 4: Managed Database Decoupling (Amazon RDS MySQL 8.0)

> **File:** `rds.tf`  
> **Architecture Level:** Tier 4 — Stateful Data Persistence Layer  
> **Security Mandate:** Zero Public Ingress, Multi-AZ Subnet Isolation, Chained Security Group (Port 3306)

---

## 🧠 Why Did We Decouple the Database?

In Phase 1 (Single Toy Server), MySQL was installed directly on the EC2 instance's local EBS volume (`apt install mysql-server`).

### The Flaws of Local MySQL on EC2:
1. **Compute and State Coupled:** If the EC2 server experiences high traffic and crashes, or if the Auto Scaling Group terminates it, **the entire WordPress database is lost!**
2. **Resource Starvation:** Both Nginx/PHP-FPM and the MySQL daemon fought for the same 1GB RAM on `t3.micro`, frequently triggering Linux Out-Of-Memory (`oom-killer`) kernel panic crashes.
3. **No Horizontal Scaling:** You cannot scale web servers from 1 to 4 instances if each server has its own separate local MySQL database.
4. **Manual Backups:** Administrators had to write fragile bash cron jobs to dump `.sql` files to disk.

---

## 🏗️ Step 4 Decoupled Production Architecture

In Step 4, we offloaded the database to **Amazon Relational Database Service (Amazon RDS)**:

```text
[ Web Server Tier: Auto Scaling Group ]
   │
   │  Private VPC Ingress on Port 3306
   ▼  (Strictly from wp-lab-web-sg only!)
[ Amazon RDS MySQL 8.0: wp-lab-db ]
   ├── Multi-AZ Private Subnet Placement:
   │     ├── Primary AZ: ap-south-1a (10.0.11.0/24)
   │     └── Standby AZ: ap-south-1b (10.0.12.0/24)
   ├── General Purpose SSD: 20 GB gp3 (Baseline 3,000 IOPS)
   ├── Storage Autoscaling: Up to 50 GB
   └── Automated Snapshots: 1-Day Daily Retention Window
```

---

## 🔍 Key Architectural Primitives

### 1. `aws_db_subnet_group.main` (Multi-AZ Private Placement)
* AWS RDS enforces an architectural rule: every DB Subnet Group must span **at least two subnets across two distinct Availability Zones**, even when provisioning a Single-AZ database.
* This ensures that if the database is upgraded to Multi-AZ failover in the future, standby subnets in alternate data centers are already registered without downtime.
* Both subnets (`10.0.11.0/24` and `10.0.12.0/24`) have **no route to the Internet Gateway**, making the database 100% invisible to external network scans.

### 2. `publicly_accessible = false` (Zero Public Ingress)
* The database instance receives only an internal private IP address inside the VPC.
* It does not have, and cannot receive, a public IPv4 address.
* External hackers cannot reach or brute force port 3306 from the outside world.

### 3. Security Group Chaining (`wp-lab-db-sg`)
* In Step 2, `aws_security_group.db` was configured with an ingress rule referencing `security_groups = [aws_security_group.web.id]`.
* Even inside the VPC, other instances or test VMs cannot connect to MySQL; **only EC2 instances tagged with the `web-sg` security group can establish database handshakes.**

### 4. Storage Autoscaling (`max_allocated_storage = 50`)
* Free tier starts at 20 GB `gp3`.
* If user comments, posts, or media metadata fill the disk, AWS automatically expands the storage volume up to 50 GB without causing downtime or database lockouts.

---

## 📊 Summary of Step 4 Outputs

| Output Variable | Description |
| :--- | :--- |
| `rds_endpoint` | Database connection string formatted as `host:port` |
| `rds_address` | RDS DNS endpoint (e.g. `wp-lab-db.xxxx.ap-south-1.rds.amazonaws.com`) consumed by `wp-config.php` |
| `rds_port` | MySQL standard listening port (`3306`) |
| `rds_database_name` | Initial schema name (`wordpress`) |
| `rds_username` | Master application username (`wpuser`) |
