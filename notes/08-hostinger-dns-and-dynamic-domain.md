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

---

## 🏛️ Deep Dive: AWS Route 53 Kahan Aur Kab Use Hota Hai?

Kayi developers is baat me confuse hote hain ki **Hostinger DNS** aur **AWS Route 53** me kya antar hai, aur Route 53 ka use kahan hota hai.

### 1. Domain Ke 3 Levels (The 3 Layers of DNS)

Internet par kisi bhi domain ke 3 alag-alag hisse hote hain:

```text
[ 1. Domain Registrar ] ────▶ Jahan se aapne domain buy kiya (e.g. Hostinger, GoDaddy, AWS)
          │
          ▼
[ 2. Nameservers (DNS Host) ] ────▶ Phonebook kiske paas hai? (Hostinger vs Route 53)
          │
          ▼
[ 3. DNS Records ] ────▶ Phonebook ke andar ke entries (A, CNAME, MX, TXT records)
```

Abhi aapke case me:
* **Registrar:** Hostinger (Aapne domain wahan se buy kiya).
* **Nameservers:** Hostinger (`solar.dns-parking.com`, `lunar.dns-parking.com`).
* **Records:** Hostinger ke DNS Zone Editor ke andar bane hain.

---

### 2. Route 53 Kahan Par Fit Hota Hai?

AWS Route 53 ko do tareeqon se use kiya jata hai:

#### Scenario A: Pure AWS (Registrar + DNS)
Aap domain hi seedha AWS Route 53 se buy karte hain. Tab Registrar aur Nameservers dono AWS ke hote hain.

#### Scenario B: DNS Delegation (Hostinger se Route 53 ko Transfer)
Aapne domain Hostinger ya GoDaddy se khareeda, lekin aap chahte hain ki saara DNS control AWS ke paas ho:
1. AWS Route 53 me **Public Hosted Zone** banta hai (`asaxenadev.com`).
2. AWS aapko **4 Nameservers** deta hai:
   * `ns-xxx.awsdns-xx.com`
   * `ns-xxx.awsdns-xx.net`
   * `ns-xxx.awsdns-xx.org`
   * `ns-xxx.awsdns-xx.co.uk`
3. Aap Hostinger me jaakar "Change Nameservers" karte hain aur Hostinger ke default nameservers hata kar AWS ke 4 nameservers paste kar dete hain.
4. **Iske baad Hostinger ka DNS band ho jata hai**, aur saare DNS records AWS Route 53 se control hote hain.

---

### 3. Route 53 vs Hostinger DNS: Comparison Table

| Feature | Hostinger DNS | AWS Route 53 |
| :--- | :--- | :--- |
| **Cost** | **Free** (Domain ke sath included) | **\$0.50/month** per hosted zone + query charges |
| **Apex / Root Domain (Alias)** | ❌ Root domain (`asaxenadev.com`) par CNAME nahi laga sakte (RFC standard). | ✅ **Route 53 Alias Record:** Root domain ko seedha ALB ya CloudFront par map kar sakte hain bina IP ke! |
| **Infrastructure as Code (Terraform)**| ❌ Manual clicks in Hostinger UI (ClickOps). | ✅ **100% Terraform Automated (`route53.tf`)**. Har record code se create/destroy hota hai. |
| **Health Checks & Failover** | ❌ Static records only. | ✅ Agar Mumbai region down ho jaye, toh traffic automatically Singapore region me bhej deta hai. |
| **Latency / Geo-Routing** | ❌ Sabhi users ko same record milta hai. | ✅ US ke user ko US server aur India ke user ko Mumbai server bhej sakta hai. |
| **Private VPC DNS** | ❌ Sirf public internet ke liye hai. | ✅ **Private Hosted Zones:** Internal VPC services ke liye private domains bana sakte hain. |

---

### 4. Hamare Case Me Hostinger Kyun Best Hai?

* Hamari target website ek **Subdomain** hai (`lab.asaxenadev.com`), root domain nahi.
* DNS standards ke according, subdomains par **CNAME** lagana 100% supported aur standard hai.
* Isliye Hostinger me 1 CNAME record add karne se kaam:
  * **Zero extra cost (\$0/month)** me ho jata hai.
  * Bina kisi nameserver propagation delay ke **30 seconds** me live ho jata hai!
