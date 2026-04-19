# FairGig — Full Project Summary

**FairGig** is a production-grade microservices platform designed to protect gig workers in Pakistan from platform exploitation. It achieves this through real-time anomaly detection, fairness scoring, and verifiable income records, serving as an end-to-end solution for a national-level hackathon.

---

## 1. System Architecture & Tech Stack

The platform is split into a robust backend architecture composed of 6 microservices running in parallel, governed by a unified MongoDB cluster, and a premium frontend interface.

### Backend (Microservices)
- **Auth Service:** (`Node.js/Express`) Handles JWT generation, password hashing (bcrypt), and Role-Based Access Control (RBAC) separating workers, verifiers, and advocates.
- **Grievance Service:** (`Node.js/Express`) Manages complaint ticketing and uses TF-IDF clustering to group similar grievances automatically.
- **Earnings Service:** (`FastAPI/Python`) The gateway for logging income, executing database reads/writes with async Motor, and interacting with other services.
- **Anomaly Service:** (`FastAPI/Python`) A pure-computational service using z-scores and standard deviations to detect sudden income drops or high deduction ratios without persisting state.
- **Analytics Service:** (`FastAPI/Python`) A privacy-first analytical engine that aggregates city and platform medians and computes the multi-variable **Fairness Score** (only surfacing cohorts of 5+ workers).
- **Certificate Service:** (`FastAPI/Python`) Provides cryptographic validation paths for the trusted earnings data.

### Database
- **MongoDB:** A single unified database cluster housing `users`, `earnings`, and `complaints` collections with optimized compound indexes for lightning-fast aggregation queries.

### Frontend
- **Stack:** `React 18`, `Vite`, `Tailwind CSS v4`, `Recharts`, `Framer Motion`.

---

## 2. Platform Interfaces (Frontend Pages)

### Earnings Logger (`/earnings`)
**Target User:** Gig Workers (Uber, Foodpanda, Fiverr)
- **Features:** Glassmorphic logging forms capturing gross earnings, hours, and deductions.
- **Insights:** Includes an `AreaChart` mapping Net vs. Deductions over time and a "Smart Alert" system triggering when anomaly thresholds are breached.

### Verification Panel (`/verify`)
**Target User:** Platform Verifiers
- **Features:** A specialized moderation grid enabling human review of worker-submitted income evidence.
- **Insights:** Facilitates rapid Approve/Reject actions based on gross vs. net financial breakdowns.

### Grievance Board (`/grievance`)
**Target User:** Gig Workers
- **Features:** An intuitive form interface for lodging formal complaints against unpredictable platform behavior.
- **Insights:** A chronological history feed using AI-generated tags (e.g. `#AccountBlocked`) to track the life-cycle of open, under-review, and resolved complaints.

### Advocate Dashboard (`/advocate`)
**Target User:** Worker Advocates & Analysts
- **Features:** A system-wide analytics hub to monitor gig worker vulnerabilities at scale.
- **Insights:** Uses a `RadarChart` to map out the "Fairness Matrix" for different platforms alongside a Vulnerability Flags table highlighting high-risk geo-locations and platform anomalies.

### Income Certificate (`/certificate`)
**Target User:** Workers / Verifiers
- **Features:** Generating a visually authoritative, printable document that represents verified income levels.
- **Insights:** Employs formal typography, watermarks, and a live QR code so workers have verifiable proof of stable earnings for essential services like housing or banking.

---

## 3. Core Workflow

1. A **Worker** logs their daily earnings.
2. The **Earnings Service** immediately sends this payload to the **Anomaly Service** for statistical evaluation (z-scores).
3. Evidence is queued for human review. A **Verifier** logs in and approves the log using the Verification Panel.
4. Aggregated data is routed through the **Analytics Service** to compute the overall exact Fairness Score of that app.
5. An **Advocate** analyzes these scores on their dashboard to protect worker rights.
6. The **Worker** generates a QR-backed **Certificate** based on their newly verified, tamper-proof income data.
