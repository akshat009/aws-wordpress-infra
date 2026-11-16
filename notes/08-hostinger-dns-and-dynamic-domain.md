# 🌐 Hostinger DNS Setup & Dynamic Domain Integration

> **Target Domain:** `lab.asaxenadev.com`  
> **Registrar / DNS Provider:** Hostinger (`solar.dns-parking.com` & `lunar.dns-parking.com`)  
> **Target ALB Endpoint:** `wp-lab-alb-1967814929.ap-south-1.elb.amazonaws.com`

---

## 🔍 Background & Architecture

Your domain `asaxenadev.com` is hosted on **Hostinger DNS**.
Previously in Phase 1 & 2 of the manual ClickOps lab:
* An **`A` record** for `lab.asaxenadev.com` was pointed directly to an EC2 Elastic IP (`43.205.26.235`).

In our new enterprise architecture:
* We do **not** use static IPs.
* Traffic routes through the **AWS Application Load Balancer (ALB)** across multiple Availability Zones.

---

## 🛠️ Step-by-Step Hostinger DNS Update (Takes 30 Seconds)

1. Log into your **Hostinger Control Panel** ([hpanel.hostinger.com](https://hpanel.hostinger.com)).
2. Navigate to **Domains** ➔ Select **`asaxenadev.com`**.
3. In the left navigation menu, click **DNS / Nameservers** (or **DNS Zone Editor**).
4. Locate the existing record for **`lab`**:
   * Delete or Edit the old `A` record pointing to `43.205.26.235`.
5. Add/Update the new **CNAME Record**:
   * **Type:** `CNAME`
   * **Name / Host:** `lab`
   * **Target / Points to:** `wp-lab-alb-1967814929.ap-south-1.elb.amazonaws.com`
   * **TTL:** `300` (or default)
6. Click **Save** or **Update**.

---

## 🧠 Dynamic Domain & Reverse Proxy Patch

To prevent WordPress from hardcoding a single domain or suffering redirect loops between the ALB DNS and `lab.asaxenadev.com`, we injected dynamic host resolution into `wp-config.php`:

```php
// Reverse Proxy & Dynamic Host Configuration (ALB & Custom Domain)
if (isset($_SERVER['HTTP_X_FORWARDED_PROTO']) && $_SERVER['HTTP_X_FORWARDED_PROTO'] === 'https') {
    $_SERVER['HTTPS'] = 'on';
}
if (isset($_SERVER['HTTP_HOST'])) {
    $http_protocol = (isset($_SERVER['HTTPS']) && $_SERVER['HTTPS'] === 'on') ? 'https://' : 'http://';
    define('WP_HOME', $http_protocol . $_SERVER['HTTP_HOST']);
    define('WP_SITEURL', $http_protocol . $_SERVER['HTTP_HOST']);
}
```

### Benefits:
1. **Multi-Domain Resilient:** You can access and administer WordPress from `http://wp-lab-alb-1967814929.ap-south-1.elb.amazonaws.com` or `http://lab.asaxenadev.com` interchangeably.
2. **Zero Database Migrations:** No need to run SQL search-and-replace queries when switching domains or adding SSL certificates.
