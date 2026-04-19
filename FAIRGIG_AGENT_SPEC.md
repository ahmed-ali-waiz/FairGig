# FairGig — Full Agent Specification
# National Hackathon 2025 | Pakistan Gig Worker Protection Platform
# This file is the single source of truth for all AI agents building this system.
# Read every section before writing any code.

---

## IDENTITY & MISSION

You are building **FairGig** — a production-grade microservices platform that protects gig workers in Pakistan from platform exploitation through real-time anomaly detection, fairness scoring, and verifiable income records.

This is a national-level hackathon project. The bar is: **real startup product, not a student project.**

Every line of code you write must be:
- Functional (not mocked, not hardcoded)
- Clean (readable, structured, consistent naming)
- Fast (optimized queries, minimal inter-service calls)
- Professional (error handling, validation, HTTP status codes)

---

## SYSTEM OVERVIEW

### Stack
- **Auth Service**: Node.js + Express + MongoDB
- **Grievance Service**: Node.js + Express + MongoDB
- **Earnings Service**: FastAPI + Python + Motor (async MongoDB)
- **Anomaly Service**: FastAPI + Python (pure computation, no DB)
- **Analytics Service**: FastAPI + Python + Motor (async MongoDB)
- **Certificate Service**: FastAPI + Python + Motor (async MongoDB)
- **Frontend**: React 18 + Vite + Tailwind CSS + Recharts + Framer Motion
- **Database**: MongoDB (single cluster, multiple collections)
- **Auth**: JWT (HS256, 7-day expiry, role embedded in payload)

### Ports
```
Auth Service        → http://localhost:3001
Grievance Service   → http://localhost:3002
Earnings Service    → http://localhost:8001
Anomaly Service     → http://localhost:8002
Analytics Service   → http://localhost:8003
Certificate Service → http://localhost:8004
Frontend            → http://localhost:5173
```

### Monorepo Structure
```
fairgig/
├── services/
│   ├── auth/               # Node.js
│   ├── grievance/          # Node.js
│   ├── earnings/           # FastAPI
│   ├── anomaly/            # FastAPI
│   ├── analytics/          # FastAPI
│   └── certificate/        # FastAPI
├── frontend/               # React + Vite
├── seed/                   # MongoDB seed scripts
├── shared/                 # JWT secret, shared constants
├── docker-compose.yml
└── README.md
```

---

## ENVIRONMENT VARIABLES

Every service reads from a `.env` file. Create `.env.example` in each service.

```env
# Shared across all services
MONGODB_URI=mongodb://localhost:27017/fairgig
JWT_SECRET=fairgig_super_secret_key_2025
JWT_EXPIRY=7d

# Service URLs (used for inter-service calls)
ANOMALY_SERVICE_URL=http://localhost:8002
ANALYTICS_SERVICE_URL=http://localhost:8003
AUTH_SERVICE_URL=http://localhost:3001

# FastAPI
HOST=0.0.0.0
PORT=8001  # change per service
```

---

## DATABASE SPECIFICATION

### MongoDB Connection
- Single MongoDB instance: database name `fairgig`
- All services connect to the same cluster
- Use Motor (async) for FastAPI services
- Use Mongoose for Node.js services

### Collection: `users`

```javascript
// Mongoose Schema (auth service)
{
  _id: ObjectId,
  name: String,           // required, min 2 chars
  email: String,          // required, unique, lowercase
  passwordHash: String,   // bcrypt, 12 rounds, NEVER return this field
  role: String,           // enum: ["worker", "verifier", "advocate"]
  city: String,           // enum: ["Lahore", "Karachi", "Islamabad"]
  platforms: [String],    // enum values: "Uber", "Foodpanda", "Fiverr"
  isActive: Boolean,      // default: true
  createdAt: Date         // auto
}

// Indexes
db.users.createIndex({ email: 1 }, { unique: true })
db.users.createIndex({ city: 1 })
db.users.createIndex({ role: 1 })
```

### Collection: `earnings`

```javascript
// Motor document structure (earnings service)
{
  _id: ObjectId,
  workerId: ObjectId,         // required, ref: users — INDEXED
  platform: String,           // enum: ["Uber", "Foodpanda", "Fiverr"] — INDEXED
  city: String,               // enum: ["Lahore", "Karachi", "Islamabad"]
  date: Date,                 // required — INDEXED
  grossEarnings: Number,      // PKR, required, min 0
  deductions: Number,         // PKR, required, min 0
  netEarnings: Number,        // computed: grossEarnings - deductions
  hoursWorked: Number,        // required, min 0.5
  screenshotUrl: String,      // optional, storage reference
  verificationStatus: String, // enum: ["pending","verified","rejected"], default: "pending"
  verifiedBy: ObjectId,       // optional, ref: users (verifier)
  verifiedAt: Date,           // optional
  anomalyFlag: Boolean,       // default: false
  anomalyDetails: {           // populated by Anomaly Service
    type: String,
    severity: String,         // "low" | "medium" | "high"
    zscore: Number,
    explanation: String,      // human-readable, shown to worker
    recommendation: String
  },
  importedFromCsv: Boolean,   // default: false
  createdAt: Date             // auto
}

// Indexes — MUST create all of these
db.earnings.createIndex({ workerId: 1 })
db.earnings.createIndex({ date: -1 })
db.earnings.createIndex({ platform: 1 })
db.earnings.createIndex({ city: 1 })
db.earnings.createIndex({ verificationStatus: 1 })
db.earnings.createIndex({ workerId: 1, date: -1 })  // compound
```

### Collection: `complaints`

```javascript
// Mongoose Schema (grievance service)
{
  _id: ObjectId,
  workerId: ObjectId,       // required, ref: users — INDEXED
  platform: String,         // required, enum: ["Uber", "Foodpanda", "Fiverr"]
  city: String,             // required
  title: String,            // required, max 120 chars
  description: String,      // required, max 2000 chars
  tags: [String],           // auto-generated from text analysis
  clusterId: String,        // assigned by clustering algorithm
  clusterLabel: String,     // human-readable cluster name
  status: String,           // enum: ["open","under_review","resolved","dismissed"]
  assignedTo: ObjectId,     // optional, ref: users (advocate)
  createdAt: Date,          // auto
  updatedAt: Date           // auto
}

// Indexes
db.complaints.createIndex({ workerId: 1 })
db.complaints.createIndex({ platform: 1 })
db.complaints.createIndex({ clusterId: 1 })
db.complaints.createIndex({ status: 1 })
db.complaints.createIndex({ createdAt: -1 })
```

---

## SERVICE 1: AUTH SERVICE (Node.js)

### File Structure
```
services/auth/
├── src/
│   ├── controllers/authController.js
│   ├── middleware/
│   │   ├── authMiddleware.js     # JWT verify + attach user to req
│   │   └── rbacMiddleware.js     # role check factory
│   ├── models/User.js
│   ├── routes/authRoutes.js
│   └── app.js
├── .env
├── .env.example
├── package.json
└── README.md
```

### API Endpoints

#### POST /auth/register
```
Request:  { name, email, password, role, city, platforms[] }
Response: { token, user: { _id, name, email, role, city, platforms } }
Rules:
  - Hash password with bcrypt (12 rounds)
  - Return JWT immediately on register
  - Never return passwordHash in any response
```

#### POST /auth/login
```
Request:  { email, password }
Response: { token, user: { _id, name, email, role, city, platforms } }
Rules:
  - Compare with bcrypt.compare
  - Return 401 with message "Invalid credentials" on failure (do not distinguish email vs password)
```

#### GET /auth/me
```
Headers:  Authorization: Bearer <token>
Response: { _id, name, email, role, city, platforms, createdAt }
Rules:
  - Verify JWT, return decoded user data from DB
  - Return 401 if token missing or invalid
```

#### PATCH /auth/me
```
Headers:  Authorization: Bearer <token>
Request:  { name?, city?, platforms? }  // only these fields updatable
Response: { _id, name, email, role, city, platforms }
```

### JWT Payload Structure
```javascript
{
  sub: userId,          // MongoDB ObjectId as string
  email: user.email,
  role: user.role,      // "worker" | "verifier" | "advocate"
  city: user.city,
  iat: issuedAt,
  exp: expiresAt        // 7 days
}
```

### Shared Auth Middleware (copy to every service)
```javascript
// shared/authMiddleware.js
const jwt = require('jsonwebtoken');

const authenticate = (req, res, next) => {
  const header = req.headers.authorization;
  if (!header || !header.startsWith('Bearer ')) {
    return res.status(401).json({ error: 'No token provided' });
  }
  const token = header.split(' ')[1];
  try {
    req.user = jwt.verify(token, process.env.JWT_SECRET);
    next();
  } catch (err) {
    return res.status(401).json({ error: 'Invalid or expired token' });
  }
};

const requireRole = (...roles) => (req, res, next) => {
  if (!roles.includes(req.user?.role)) {
    return res.status(403).json({ error: 'Insufficient permissions' });
  }
  next();
};

module.exports = { authenticate, requireRole };
```

### FastAPI Auth Dependency (copy to every FastAPI service)
```python
# shared/auth.py
from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
import jwt
import os

security = HTTPBearer()

def get_current_user(credentials: HTTPAuthorizationCredentials = Depends(security)):
    try:
        payload = jwt.decode(
            credentials.credentials,
            os.getenv("JWT_SECRET"),
            algorithms=["HS256"]
        )
        return payload
    except jwt.ExpiredSignatureError:
        raise HTTPException(status_code=401, detail="Token expired")
    except jwt.InvalidTokenError:
        raise HTTPException(status_code=401, detail="Invalid token")

def require_role(*roles):
    def dependency(user=Depends(get_current_user)):
        if user.get("role") not in roles:
            raise HTTPException(status_code=403, detail="Insufficient permissions")
        return user
    return dependency
```

---

## SERVICE 2: EARNINGS SERVICE (FastAPI)

### File Structure
```
services/earnings/
├── app/
│   ├── main.py
│   ├── routers/
│   │   └── earnings.py
│   ├── models/
│   │   └── earnings.py      # Pydantic models
│   ├── db/
│   │   └── mongo.py         # Motor connection
│   └── services/
│       ├── anomaly_client.py   # calls Anomaly Service
│       └── analytics_client.py # calls Analytics Service
├── requirements.txt
├── .env
└── README.md
```

### Pydantic Models
```python
from pydantic import BaseModel, Field
from typing import Optional, List
from datetime import date
from enum import Enum

class Platform(str, Enum):
    uber = "Uber"
    foodpanda = "Foodpanda"
    fiverr = "Fiverr"

class City(str, Enum):
    lahore = "Lahore"
    karachi = "Karachi"
    islamabad = "Islamabad"

class EarningsCreate(BaseModel):
    platform: Platform
    city: City
    date: date
    grossEarnings: float = Field(..., gt=0)
    deductions: float = Field(..., ge=0)
    hoursWorked: float = Field(..., gt=0)
    screenshotUrl: Optional[str] = None

class EarningsResponse(BaseModel):
    id: str
    workerId: str
    platform: str
    city: str
    date: str
    grossEarnings: float
    deductions: float
    netEarnings: float
    hoursWorked: float
    screenshotUrl: Optional[str]
    verificationStatus: str
    anomalyFlag: bool
    anomalyDetails: Optional[dict]
    createdAt: str
```

### API Endpoints

#### GET /earnings
```
Auth: worker
Query params: page=1, limit=20, platform?, startDate?, endDate?
Response: { earnings: [...], total: int, page: int, pages: int }
Query: filter by workerId from JWT, sort by date desc
```

#### POST /earnings
```
Auth: worker
Request: EarningsCreate
Flow:
  1. Compute netEarnings = grossEarnings - deductions
  2. Insert document with workerId from JWT
  3. IMMEDIATELY call Anomaly Service: POST http://ANOMALY_URL/anomaly/detect
     Payload: { workerId, platform, grossEarnings, deductions, netEarnings, hoursWorked, date }
  4. Update document with anomaly result (anomalyFlag, anomalyDetails)
  5. Return full document including anomaly result
Response: EarningsResponse (with anomaly data populated)
```

#### GET /earnings/dashboard
```
Auth: worker
Flow:
  1. Aggregate worker's earnings for current week and month
  2. Call Analytics Service: GET http://ANALYTICS_URL/analytics/city-median?city=X&platform=X
  3. Build smart alerts array from recent anomaly flags
  4. Compute fairness scores per platform used by this worker
Response: {
  summary: { weekGross, weekNet, weekDeductions, monthGross, monthNet },
  cityComparison: { workerMedian, cityMedian, percentageDiff, message },
  alerts: [{ type, severity, message, date }],
  fairnessScores: { Uber?: number, Foodpanda?: number, Fiverr?: number },
  weeklyTrend: [{ week, gross, net, deductions }],  // last 8 weeks
  recentEntries: [...]  // last 5
}
```

#### GET /earnings/{id}
```
Auth: worker | verifier
Rules: worker can only access own records
Response: Full EarningsResponse
```

#### PATCH /earnings/{id}
```
Auth: worker
Rules: can only update own records, cannot change verificationStatus
Request: { date?, grossEarnings?, deductions?, hoursWorked?, screenshotUrl? }
```

#### DELETE /earnings/{id}
```
Auth: worker
Rules: can only delete own records with verificationStatus = "pending"
Response: { message: "Deleted successfully" }
```

#### POST /earnings/import-csv
```
Auth: worker
Request: multipart/form-data, file field = "csv"
Expected CSV columns: date,platform,gross_earnings,deductions,hours_worked
Optional columns: screenshot_url,notes
Flow:
  1. Parse CSV with Python csv module
  2. Validate each row
  3. For each valid row: insert + call Anomaly Service
  4. Return summary: { imported: int, failed: int, errors: [{ row, reason }] }
```

#### POST /earnings/{id}/upload-screenshot
```
Auth: worker
Request: multipart/form-data, file field = "screenshot"
Flow: Save to local storage at /uploads/{workerId}/{filename}, update screenshotUrl
Response: { screenshotUrl: string }
```

#### PATCH /earnings/{id}/verify
```
Auth: verifier
Request: { status: "verified" | "rejected", notes?: string }
Flow: Update verificationStatus, verifiedBy (from JWT), verifiedAt
Response: Updated EarningsResponse
```

### Anomaly Client Implementation
```python
# services/anomaly_client.py
import httpx
import os
import logging

ANOMALY_URL = os.getenv("ANOMALY_SERVICE_URL", "http://localhost:8002")

async def detect_anomaly(payload: dict) -> dict:
    """Call Anomaly Service. Returns empty result on failure — never block earnings save."""
    try:
        async with httpx.AsyncClient(timeout=3.0) as client:
            response = await client.post(f"{ANOMALY_URL}/anomaly/detect", json=payload)
            if response.status_code == 200:
                return response.json()
    except Exception as e:
        logging.warning(f"Anomaly service unavailable: {e}")
    return {"anomalyDetected": False, "anomalies": [], "overallRisk": "low"}
```

---

## SERVICE 3: ANOMALY SERVICE (FastAPI)

### Key Rule
This service has NO database. It is a pure computation service. It receives data, runs algorithms, and returns results synchronously.

### File Structure
```
services/anomaly/
├── app/
│   ├── main.py
│   ├── routers/
│   │   └── anomaly.py
│   └── services/
│       └── detector.py      # all detection logic here
├── requirements.txt
└── README.md
```

### API Endpoints

#### POST /anomaly/detect
```
Request: {
  workerId: string,
  platform: string,
  grossEarnings: float,
  deductions: float,
  netEarnings: float,
  hoursWorked: float,
  date: string,
  recentHistory?: [{ netEarnings, deductions, grossEarnings, hoursWorked, date }]
}
Response: {
  anomalyDetected: boolean,
  anomalies: [
    {
      type: string,         // "income_drop" | "high_deductions" | "abnormal_hourly"
      severity: string,     // "low" | "medium" | "high"
      zscore: float,
      threshold: float,
      explanation: string,  // human-readable, plain English
      recommendation: string
    }
  ],
  overallRisk: string       // "low" | "medium" | "high"
}
```

### Detection Implementation
```python
# services/detector.py
import numpy as np
from typing import List, Dict, Any

THRESHOLDS = {
    "income_drop_zscore": -1.5,       # ~20% drop
    "high_deduction_ratio": 0.35,     # 35% of gross
    "deduction_zscore": 1.5,          # 1.5 std devs above mean
    "hourly_rate_zscore": -2.0,       # severe hourly drop
}

def compute_zscore(value: float, mean: float, std: float) -> float:
    if std == 0:
        return 0.0
    return (value - mean) / std

def detect_income_drop(current_net: float, history: List[float]) -> Dict:
    if len(history) < 3:
        return None
    mean = np.mean(history)
    std = np.std(history)
    zscore = compute_zscore(current_net, mean, std)
    if zscore < THRESHOLDS["income_drop_zscore"]:
        pct_drop = round(abs((current_net - mean) / mean) * 100, 1)
        severity = "high" if zscore < -2.5 else "medium" if zscore < -2.0 else "low"
        return {
            "type": "income_drop",
            "severity": severity,
            "zscore": round(zscore, 3),
            "threshold": THRESHOLDS["income_drop_zscore"],
            "explanation": f"Your net earnings (PKR {current_net:,.0f}) are {pct_drop}% below your recent average of PKR {mean:,.0f}.",
            "recommendation": "Review if platform commission rates changed or if there were fewer orders this period."
        }
    return None

def detect_high_deductions(gross: float, deductions: float, history_deduction_ratios: List[float]) -> Dict:
    current_ratio = deductions / gross if gross > 0 else 0
    if current_ratio > THRESHOLDS["high_deduction_ratio"]:
        if len(history_deduction_ratios) >= 3:
            mean = np.mean(history_deduction_ratios)
            std = np.std(history_deduction_ratios)
            zscore = compute_zscore(current_ratio, mean, std)
        else:
            zscore = 1.5  # default flag
        pct = round(current_ratio * 100, 1)
        return {
            "type": "high_deductions",
            "severity": "high" if current_ratio > 0.45 else "medium",
            "zscore": round(zscore, 3),
            "threshold": THRESHOLDS["high_deduction_ratio"],
            "explanation": f"Deductions are {pct}% of your gross earnings. This is unusually high.",
            "recommendation": "Check your platform's commission breakdown. Consider switching to higher-margin order types."
        }
    return None

def detect_abnormal_hourly(current_net: float, hours: float, history_hourly: List[float]) -> Dict:
    if hours <= 0 or len(history_hourly) < 3:
        return None
    hourly_rate = current_net / hours
    mean = np.mean(history_hourly)
    std = np.std(history_hourly)
    zscore = compute_zscore(hourly_rate, mean, std)
    if zscore < THRESHOLDS["hourly_rate_zscore"]:
        return {
            "type": "abnormal_hourly",
            "severity": "medium",
            "zscore": round(zscore, 3),
            "threshold": THRESHOLDS["hourly_rate_zscore"],
            "explanation": f"Your hourly rate (PKR {hourly_rate:,.0f}/hr) is far below your usual PKR {mean:,.0f}/hr.",
            "recommendation": "High-traffic hours may have had lower orders. Consider working peak hours."
        }
    return None

def run_all_detectors(payload: dict, history: List[dict]) -> dict:
    history_net = [h["netEarnings"] for h in history]
    history_hourly = [h["netEarnings"] / h["hoursWorked"] for h in history if h["hoursWorked"] > 0]
    history_deduction_ratios = [h["deductions"] / h["grossEarnings"] for h in history if h["grossEarnings"] > 0]

    anomalies = []

    result = detect_income_drop(payload["netEarnings"], history_net)
    if result:
        anomalies.append(result)

    result = detect_high_deductions(payload["grossEarnings"], payload["deductions"], history_deduction_ratios)
    if result:
        anomalies.append(result)

    result = detect_abnormal_hourly(payload["netEarnings"], payload["hoursWorked"], history_hourly)
    if result:
        anomalies.append(result)

    severities = [a["severity"] for a in anomalies]
    overall = "high" if "high" in severities else "medium" if "medium" in severities else "low" if anomalies else "low"

    return {
        "anomalyDetected": len(anomalies) > 0,
        "anomalies": anomalies,
        "overallRisk": overall
    }
```

---

## SERVICE 4: ANALYTICS SERVICE (FastAPI)

### Privacy Rule
**This service NEVER returns individual worker data. Minimum cohort = 5 workers before surfacing any stat. All responses are aggregated.**

### API Endpoints

#### GET /analytics/city-median
```
Auth: any authenticated user
Query: city (required), platform (required), period="week"|"month" (default: "month")
Response: {
  city: string,
  platform: string,
  period: string,
  median_net: float,
  median_gross: float,
  median_deduction_pct: float,
  sample_size: int,
  computed_at: string
}

MongoDB Aggregation (Motor):
db.earnings.aggregate([
  { $match: { city, platform, date: { $gte: periodStart } } },
  { $group: { _id: null,
      median_net: { $median: { input: "$netEarnings", method: "approximate" } },
      median_gross: { $median: { input: "$grossEarnings", method: "approximate" } },
      count: { $sum: 1 }
  }},
  { $match: { count: { $gte: 5 } } }  // privacy floor
])
```

#### GET /analytics/fairness-score
```
Auth: any authenticated user
Query: platform (required), city (optional)
Response: {
  platform: string,
  score: int,           // 0-100
  breakdown: {
    deduction_score: float,    // 0-40
    stability_score: float,    // 0-30
    anomaly_score: float       // 0-30
  },
  interpretation: string,      // "Poor" | "Fair" | "Good" | "Excellent"
  sample_size: int
}

Fairness Score Formula:
  deduction_score = max(0, 40 - (median_deduction_pct / 50 * 40))
  stability_score = max(0, 30 - (net_earnings_std_dev / median_net * 30))
  anomaly_score   = max(0, 30 - (anomaly_rate * 30))
  total = round(deduction_score + stability_score + anomaly_score)
  interpretation: 0-30="Poor", 31-50="Fair", 51-75="Good", 76-100="Excellent"
```

#### GET /analytics/trends
```
Auth: any authenticated user
Query: platform (required), city (optional), weeks=12
Response: {
  platform: string,
  trend: [
    { week: "2025-W01", avg_net: float, avg_deduction_pct: float, count: int }
  ]
}
```

#### GET /analytics/platform-compare
```
Auth: worker (uses their city from JWT)
Response: {
  city: string,
  platforms: [
    { platform, fairness_score, median_net, median_deduction_pct, sample_size }
  ]
}
```

#### GET /analytics/vulnerability-flags
```
Auth: advocate only
Response: {
  flags: [
    { city, platform, anomaly_rate: float, affected_workers_approx: int, top_anomaly_type: string }
  ]
}
Rules: anomaly_rate = (records with anomalyFlag=true) / total records, grouped by city+platform
```

---

## SERVICE 5: GRIEVANCE SERVICE (Node.js)

### File Structure
```
services/grievance/
├── src/
│   ├── controllers/grievanceController.js
│   ├── models/Complaint.js
│   ├── routes/grievanceRoutes.js
│   ├── services/
│   │   └── clusteringService.js   # TF-IDF + cosine similarity
│   └── app.js
├── package.json
└── README.md
```

### API Endpoints

#### POST /grievance
```
Auth: worker
Request: { platform, title, description }
Flow:
  1. Extract tags from title + description (top 5 nouns/keywords)
  2. Run clustering: compare against existing cluster centroids
  3. Assign clusterId + clusterLabel (or create new cluster)
  4. Save complaint
Response: Full complaint document
```

#### GET /grievance
```
Auth: worker
Response: worker's own complaints, sorted by createdAt desc
```

#### GET /grievance/all
```
Auth: verifier | advocate
Query: status?, platform?, city?, page=1, limit=20
Response: { complaints: [...], total, page, pages }
```

#### GET /grievance/clusters
```
Auth: advocate | verifier
Response: {
  clusters: [
    {
      clusterId: string,
      label: string,
      count: int,
      platforms: [string],
      cities: [string],
      topKeywords: [string],
      recentComplaints: [{ _id, title, platform, city, status, createdAt }]
    }
  ]
}
```

#### PATCH /grievance/:id
```
Auth: advocate
Request: { status?, assignedTo?, notes? }
Response: Updated complaint
```

#### DELETE /grievance/:id
```
Auth: worker
Rules: can only delete own complaints with status = "open"
```

### Clustering Implementation
```javascript
// services/clusteringService.js
const SIMILARITY_THRESHOLD = 0.65;

function tokenize(text) {
  return text.toLowerCase()
    .replace(/[^\w\s]/g, '')
    .split(/\s+/)
    .filter(w => w.length > 3 && !STOPWORDS.includes(w));
}

function computeTfIdf(tokens, allDocuments) {
  const tf = {};
  tokens.forEach(t => tf[t] = (tf[t] || 0) + 1 / tokens.length);
  const idf = {};
  Object.keys(tf).forEach(term => {
    const docsWithTerm = allDocuments.filter(doc => doc.includes(term)).length;
    idf[term] = Math.log((allDocuments.length + 1) / (docsWithTerm + 1));
  });
  const vector = {};
  Object.keys(tf).forEach(t => vector[t] = tf[t] * idf[t]);
  return vector;
}

function cosineSimilarity(vec1, vec2) {
  const keys = new Set([...Object.keys(vec1), ...Object.keys(vec2)]);
  let dot = 0, mag1 = 0, mag2 = 0;
  keys.forEach(k => {
    dot += (vec1[k] || 0) * (vec2[k] || 0);
    mag1 += ((vec1[k] || 0) ** 2);
    mag2 += ((vec2[k] || 0) ** 2);
  });
  return mag1 && mag2 ? dot / (Math.sqrt(mag1) * Math.sqrt(mag2)) : 0;
}

async function assignCluster(complaint, Complaint) {
  const existing = await Complaint.find({}, 'title description tags clusterId clusterLabel').lean();
  const allDocs = existing.map(c => tokenize(c.title + ' ' + c.description));
  const newTokens = tokenize(complaint.title + ' ' + complaint.description);
  const newVector = computeTfIdf(newTokens, allDocs);

  // Find best matching cluster
  const clusterGroups = {};
  existing.forEach(c => {
    if (!clusterGroups[c.clusterId]) clusterGroups[c.clusterId] = { docs: [], label: c.clusterLabel };
    clusterGroups[c.clusterId].docs.push(tokenize(c.title + ' ' + c.description));
  });

  let bestCluster = null, bestSim = 0;
  Object.entries(clusterGroups).forEach(([clusterId, { docs, label }]) => {
    const centroidTokens = docs.flat();
    const centroidVector = computeTfIdf(centroidTokens, allDocs);
    const sim = cosineSimilarity(newVector, centroidVector);
    if (sim > bestSim) { bestSim = sim; bestCluster = { clusterId, label }; }
  });

  if (bestSim >= SIMILARITY_THRESHOLD && bestCluster) {
    return { clusterId: bestCluster.clusterId, clusterLabel: bestCluster.label };
  }

  // Create new cluster
  const topKeywords = Object.entries(newVector).sort((a, b) => b[1] - a[1]).slice(0, 3).map(([k]) => k);
  const newClusterId = `cluster_${Date.now()}`;
  const newLabel = topKeywords.join(' ') || 'general complaint';
  return { clusterId: newClusterId, clusterLabel: newLabel };
}

const STOPWORDS = ['that', 'this', 'with', 'from', 'have', 'they', 'will', 'been', 'were', 'their'];

module.exports = { assignCluster, tokenize };
```

---

## SERVICE 6: CERTIFICATE SERVICE (FastAPI)

### API Endpoints

#### GET /certificate/{workerId}
```
Auth: worker (can only access own) | verifier | advocate
Query: startDate?, endDate?, platform?
Response: HTML document (Content-Type: text/html)
Rules:
  - Only include earnings with verificationStatus = "verified"
  - Aggregate by month
  - If no verified earnings: return 404 with JSON { error: "No verified earnings found" }
```

### Certificate HTML Template
```python
# The certificate must include:
# - Worker name, city, platforms
# - Date range of verified earnings
# - Monthly breakdown table: Month | Platform | Gross | Deductions | Net
# - Totals row
# - "Verified by FairGig Platform" stamp with timestamp
# - Print CSS: @media print { body { margin: 0; } .no-print { display: none; } }
# - A Print button with class="no-print"
# - QR code placeholder div with text: "Verify at: fairgig.pk/verify/{workerId}"

def generate_certificate_html(worker: dict, earnings: list, date_range: dict) -> str:
    # Build month-grouped table
    # Calculate totals
    # Return complete HTML string with embedded CSS
    ...
```

---

## FRONTEND SPECIFICATION

### Setup
```bash
npm create vite@latest frontend -- --template react
cd frontend
npm install tailwindcss postcss autoprefixer recharts framer-motion axios react-router-dom react-hot-toast
npx tailwindcss init -p
```

### Design System (Tailwind config)
```javascript
// tailwind.config.js
module.exports = {
  content: ["./src/**/*.{js,jsx}"],
  theme: {
    extend: {
      colors: {
        brand: {
          50: '#F0F4FF',
          100: '#E0E9FF',
          500: '#3B6FE8',
          700: '#1E3A5F',    // 30% — primary color
          900: '#0F1F3D',
        },
        surface: '#F8FAFF',  // 60% — neutral background
        accent: {
          green: '#16A34A',  // 10% — positive accent
          red: '#DC2626',    // 10% — negative/alert accent
          amber: '#D97706',  // warnings
        }
      },
      borderRadius: { xl: '12px', '2xl': '16px' },
      boxShadow: {
        card: '0 1px 3px rgba(0,0,0,0.08), 0 1px 2px rgba(0,0,0,0.04)',
        hover: '0 4px 12px rgba(0,0,0,0.12)',
      }
    }
  }
}
```

### File Structure
```
frontend/src/
├── components/
│   ├── ui/
│   │   ├── Card.jsx           # base card with shadow + rounded corners
│   │   ├── Badge.jsx          # status badges (pending/verified/rejected)
│   │   ├── SkeletonLoader.jsx # skeleton for async content
│   │   ├── AlertBanner.jsx    # smart alert component
│   │   └── FairnessGauge.jsx  # circular gauge 0-100
│   ├── charts/
│   │   ├── EarningsTrendChart.jsx   # Recharts AreaChart
│   │   ├── PlatformCompareChart.jsx # Recharts BarChart
│   │   └── ClusterBubbleChart.jsx   # D3 or Recharts ScatterChart
│   └── layout/
│       ├── Navbar.jsx
│       └── Sidebar.jsx
├── pages/
│   ├── Dashboard.jsx
│   ├── EarningsLogger.jsx
│   ├── VerificationPanel.jsx
│   ├── GrievanceBoard.jsx
│   ├── AdvocateDashboard.jsx
│   └── CertificatePage.jsx
├── hooks/
│   ├── useEarnings.js
│   ├── useAuth.js
│   └── useGrievance.js
├── services/
│   └── api.js               # axios instance + all API calls
├── store/
│   └── authStore.js         # Zustand or Context for auth state
├── App.jsx
└── main.jsx
```

### API Service Layer
```javascript
// services/api.js
import axios from 'axios';

const API_BASES = {
  auth: 'http://localhost:3001',
  earnings: 'http://localhost:8001',
  analytics: 'http://localhost:8003',
  grievance: 'http://localhost:3002',
  certificate: 'http://localhost:8004',
};

const createClient = (base) => {
  const client = axios.create({ baseURL: base });
  client.interceptors.request.use(config => {
    const token = localStorage.getItem('fairgig_token');
    if (token) config.headers.Authorization = `Bearer ${token}`;
    return config;
  });
  client.interceptors.response.use(
    res => res,
    err => {
      if (err.response?.status === 401) {
        localStorage.removeItem('fairgig_token');
        window.location.href = '/login';
      }
      return Promise.reject(err);
    }
  );
  return client;
};

export const authApi = createClient(API_BASES.auth);
export const earningsApi = createClient(API_BASES.earnings);
export const analyticsApi = createClient(API_BASES.analytics);
export const grievanceApi = createClient(API_BASES.grievance);
export const certificateApi = createClient(API_BASES.certificate);
```

### Framer Motion Usage Rules
```javascript
// ONLY use Framer Motion for these three cases:

// 1. Page transitions — wrap every page
import { motion } from 'framer-motion';
const pageVariants = {
  initial: { opacity: 0, y: 8 },
  animate: { opacity: 1, y: 0 },
  exit: { opacity: 0, y: -8 }
};
<motion.div variants={pageVariants} initial="initial" animate="animate" exit="exit"
  transition={{ duration: 0.2 }}>

// 2. Card hover effect
<motion.div whileHover={{ y: -2, boxShadow: '0 4px 12px rgba(0,0,0,0.12)' }}
  transition={{ duration: 0.15 }}>

// 3. List item entry
const listItem = {
  hidden: { opacity: 0, x: -8 },
  show: { opacity: 1, x: 0 }
};

// DO NOT use: heavy spring physics, layout animations, drag, complex orchestration
```

---

## PAGE SPECIFICATIONS

### Page 1: Worker Dashboard (`/dashboard`)

```
Role: worker
Data sources:
  - GET /earnings/dashboard  (primary — load first)
  - Loading state: show skeleton cards

Layout (top to bottom):
  1. Smart Alert Banner
     - Show if alerts array is non-empty
     - Yellow background for medium, red for high severity
     - Text: first alert's explanation message
     - Dismissible with X button (local state only)

  2. Summary Cards Row (4 cards)
     - This Week Net: PKR {weekNet}
     - This Month Net: PKR {monthNet}
     - Deduction Rate: {(deductions/gross * 100).toFixed(1)}%
     - Hours Worked: {weekHours}h

  3. City Comparison Card
     - "You earned {X}% {more|less} than the median {city} {platform} worker this month"
     - Show both values: Your median vs City median

  4. Fairness Score Row
     - One gauge per platform the worker uses
     - FairnessGauge component: circular SVG, color: green >75, yellow 50-75, red <50
     - Label: platform name + score

  5. Weekly Earnings Trend
     - Recharts AreaChart
     - Three lines: gross, net, deductions
     - X-axis: last 8 weeks, Y-axis: PKR

  6. Recent Entries Table
     - Last 5 earnings
     - Columns: Date | Platform | Net | Deductions | Status | Anomaly
     - Status badge: pending=gray, verified=green, rejected=red
     - Anomaly badge: show red "!" if anomalyFlag=true
```

### Page 2: Earnings Logger (`/earnings`)

```
Role: worker
Tabs: [Manual Entry] [CSV Import] [History]

Manual Entry Tab:
  Form fields:
    - Platform (select: Uber | Foodpanda | Fiverr)
    - City (select: Lahore | Karachi | Islamabad)
    - Date (date picker, default today)
    - Gross Earnings (number input, PKR)
    - Deductions (number input, PKR)
    - Net (read-only, auto-computed: gross - deductions)
    - Hours Worked (number input)
    - Screenshot (file upload, accepts image/*)
  Submit: POST /earnings
  After submit:
    - Show AnomalyResultPanel (slides in from right)
    - Panel shows: risk level badge, list of anomaly explanations
    - If no anomaly: show green "All clear" message

CSV Import Tab:
  - Drag-and-drop zone
  - Show expected column format
  - Preview table of first 5 rows after file selection
  - Submit: POST /earnings/import-csv
  - Show import results: {imported} success, {failed} failed

History Tab:
  - Paginated table of all earnings
  - Filters: platform, date range, verification status
  - Each row expandable to show anomaly details
```

### Page 3: Verification Panel (`/verify`)

```
Role: verifier
Data: GET /earnings?verificationStatus=pending (across all workers)

Layout:
  - Filter bar: platform, city, date range
  - Card list of pending earnings
  - Each card shows: worker city, platform, date, gross, net, deductions, screenshot thumbnail
  - Click card → opens drawer with full details + screenshot
  - Drawer actions:
      [Verify] → PATCH /earnings/{id}/verify { status: "verified" }
      [Reject] → PATCH /earnings/{id}/verify { status: "rejected", notes: requiredInput }
  - After action: remove card from list with exit animation
```

### Page 4: Grievance Board (`/grievance`)

```
Role: worker (own), advocate (all)

Worker view:
  - [File Complaint] button → opens modal form
    Fields: platform, title (max 120), description (max 2000)
  - Own complaints list with status badges
  - Each complaint shows: clusterId label chip, tags array

Advocate view:
  - Top section: Cluster Visualization
    Use Recharts ScatterChart or simple bubble grid
    Each bubble = one cluster, size = complaint count
    Color by dominant platform
    Click bubble → filter list below
  - Below: all complaints table with filters
    Columns: Worker City | Platform | Cluster | Status | Date | Actions
    Actions: Change status, Assign to self
```

### Page 5: Advocate Dashboard (`/advocate`)

```
Role: advocate
Data sources:
  - GET /analytics/vulnerability-flags
  - GET /analytics/fairness-score (for each platform)
  - GET /analytics/trends (for each platform)
  - GET /grievance/clusters

Layout:
  1. Vulnerability Flags table
     - City | Platform | Anomaly Rate | Approx Workers Affected | Top Issue
     - Sort by anomaly rate descending
     - High rates highlighted red

  2. Platform Fairness Leaderboard
     - Three cards: Uber, Foodpanda, Fiverr
     - Large score number, color-coded
     - Breakdown bars: deduction/stability/anomaly subscores

  3. Commission Trend Chart
     - Recharts LineChart
     - Three lines: one per platform
     - X-axis: last 12 weeks
     - Y-axis: average deduction percentage

  4. Cluster Summary
     - Top 5 clusters by complaint count
     - Horizontal bar chart
```

### Page 6: Certificate Page (`/certificate`)

```
Role: worker (own)

Layout:
  - Date range picker (start, end)
  - Platform filter (optional)
  - [Generate Certificate] button
  - Preview iframe showing GET /certificate/{workerId} HTML
  - [Print] button → window.print()

If no verified earnings:
  - Show info card: "You have no verified earnings in this period. Submit earnings and ask a verifier to approve them."
```

---

## SEED DATA SPECIFICATION

### Seed Script Location
`seed/generate.js` — run with `node seed/generate.js`

### Users to Create (minimum)
```javascript
const seedUsers = [
  // Workers
  { name: "Ali Hassan",     email: "ali@test.com",     password: "password123", role: "worker",   city: "Lahore",    platforms: ["Uber", "Foodpanda"] },
  { name: "Fatima Malik",   email: "fatima@test.com",  password: "password123", role: "worker",   city: "Karachi",   platforms: ["Fiverr"] },
  { name: "Usman Tariq",    email: "usman@test.com",   password: "password123", role: "worker",   city: "Islamabad", platforms: ["Foodpanda"] },
  { name: "Ayesha Raza",    email: "ayesha@test.com",  password: "password123", role: "worker",   city: "Karachi",   platforms: ["Uber"] },
  { name: "Bilal Ahmed",    email: "bilal@test.com",   password: "password123", role: "worker",   city: "Lahore",    platforms: ["Fiverr", "Foodpanda"] },
  // + 15 more workers with varied cities and platforms
  // Verifiers
  { name: "Sara Ahmed",     email: "sara@test.com",    password: "password123", role: "verifier", city: "Lahore",    platforms: [] },
  // Advocates
  { name: "Dr. Nadia Iqbal",email: "nadia@test.com",   password: "password123", role: "advocate", city: "Karachi",   platforms: [] },
];
```

### Earnings Data Story — Ali Hassan (key demo user)
```
Ali Hassan is an Uber driver in Lahore.
Weeks 1-6: Normal earnings. Net ~PKR 12,000-14,000/week. Deductions ~18%.
Week 7: ANOMALY — income drops to PKR 8,500 (37% below his average). Flag: income_drop HIGH.
Week 8: ANOMALY — Foodpanda deductions spike to 38%. Flag: high_deductions MEDIUM.
This creates 2 visible Smart Alerts on his dashboard when demoing.
```

### Seed Volumes
```
Total earnings records: 120+ (spread across all workers, platforms, cities)
Anomaly rate target: ~15% of records flagged (natural variation)
Complaints: 25+ records spread across 4-5 clusters
Date range: last 10 weeks from script run date
```

---

## WINNING FEATURES IMPLEMENTATION

### 1. Fairness Score Display Component
```jsx
// components/ui/FairnessGauge.jsx
// SVG circular gauge, 0-100, color-coded
// score >= 76: stroke="#16A34A" (green), interpretation="Excellent"
// score >= 51: stroke="#D97706" (amber), interpretation="Good"
// score >= 31: stroke="#F59E0B" (yellow), interpretation="Fair"
// score < 31:  stroke="#DC2626" (red),   interpretation="Poor"
```

### 2. Smart Alert Banner
```jsx
// components/ui/AlertBanner.jsx
// Takes: alerts array from /earnings/dashboard
// Shows: first unread alert prominently at top of dashboard
// Text comes directly from anomaly explanation field — no transformation needed
// Severity "high" → red bg, "medium" → amber bg, "low" → blue bg
```

### 3. Storytelling Insight Generation
```javascript
// In Dashboard.jsx, after fetching dashboard data:
function generateInsight(dashboardData) {
  const { cityComparison, summary } = dashboardData;
  if (!cityComparison) return null;
  const diff = Math.abs(cityComparison.percentageDiff);
  const direction = cityComparison.percentageDiff < 0 ? 'less' : 'more';
  return `You earned ${diff.toFixed(0)}% ${direction} than the median ${cityComparison.city} worker on ${cityComparison.platform} this month.`;
}
```

### 4. Cluster Visualization
```jsx
// Use Recharts ScatterChart for simplicity
// Each cluster is a "dot" where:
//   x = cluster index
//   y = complaint count  
//   z (bubble size) = complaint count
// On click: filter complaints table to that cluster
// Label each bubble with clusterLabel (truncated to 15 chars)
```

---

## PERFORMANCE RULES

These rules are non-negotiable. Violating them makes the app feel slow.

```
1. Dashboard: fetch all data in ONE call to /earnings/dashboard
   - Do NOT make separate calls for summary, alerts, trends — one endpoint returns all

2. Anomaly detection: 3-second timeout max on inter-service call
   - If anomaly service is down, save earnings anyway, flag anomalyDetails as null
   - Never block a user action waiting for a service that might be slow

3. MongoDB queries: always include workerId in the match stage before date filtering
   - Use compound index { workerId: 1, date: -1 } for worker-specific queries

4. Frontend: never call analytics endpoints on every render
   - Cache analytics data in component state, refetch on explicit refresh

5. React: use React.memo() on chart components
   - Charts are expensive to re-render; wrap EarningsTrendChart and ClusterBubbleChart

6. Pagination: default limit=20 on all list endpoints
   - Never return unbounded arrays

7. Skeleton loaders: every data-dependent component shows skeleton while loading
   - Use a 3-pulse skeleton div while awaiting API response
```

---

## ERROR HANDLING STANDARDS

```
All API endpoints must return consistent error format:
{ "error": "Human readable message", "code": "MACHINE_READABLE_CODE" }

HTTP status codes:
  200 — success
  201 — created
  400 — validation error (bad request body)
  401 — missing or invalid token
  403 — valid token, wrong role
  404 — resource not found
  422 — unprocessable entity (FastAPI default for Pydantic errors — keep this)
  500 — internal server error (log it, return generic message to client)

Frontend error handling:
  - All API errors caught in axios interceptor
  - Toast notification for 4xx errors (react-hot-toast)
  - 401 → redirect to login
  - 500 → show "Something went wrong. Try again." toast
```

---

## README REQUIREMENTS

Each service folder must have a `README.md` with:
```markdown
# [Service Name]

## What It Does
One paragraph.

## Setup
```bash
# install
npm install  # or pip install -r requirements.txt

# env
cp .env.example .env
# edit .env

# run
npm run dev  # or uvicorn app.main:app --reload --port 8001
```

## API Endpoints
Brief table: Method | Endpoint | Auth | Description

## Environment Variables
Table of all vars, their purpose, and example values
```

---

## BUILD ORDER FOR AI AGENT

Follow this exact sequence. Do not skip steps.

```
Step 1: Create monorepo folder structure
Step 2: Set up shared JWT_SECRET in shared/ folder
Step 3: Build Auth Service — make login/register work end-to-end
Step 4: Build Anomaly Service — pure computation, no DB needed
Step 5: Build Earnings Service — wire to Anomaly Service
Step 6: Build Analytics Service — MongoDB aggregations
Step 7: Build Grievance Service — with clustering
Step 8: Build Certificate Service — HTML generation
Step 9: Write seed script and populate DB
Step 10: Build React frontend — start with auth flow
Step 11: Build Worker Dashboard — most important page
Step 12: Build remaining pages in priority order:
          EarningsLogger → VerificationPanel → GrievanceBoard → AdvocateDashboard → CertificatePage
Step 13: Test full flow: register → log earnings → see anomaly → dashboard shows alert
Step 14: Polish: skeleton loaders, error states, responsive layout
```

---

## DEMO FLOW (what the judges will see)

```
1. Open http://localhost:5173
2. Log in as ali@test.com / password123 (worker role)
3. Smart Alert banner visible at top of dashboard
4. Show Fairness Score gauges — Foodpanda scores low
5. Navigate to Earnings Logger
6. Add a new entry — watch anomaly result panel slide in
7. Navigate back to Dashboard — new alert appears
8. Log in as sara@test.com (verifier) — verify an earnings record
9. Log in as ali@test.com — generate Income Certificate (shows verified earnings only)
10. Log in as nadia@test.com (advocate) — show cluster visualization on Grievance Board
11. Show Advocate Dashboard — vulnerability flags table
12. Open http://localhost:8001/docs — show live Swagger API docs
```

---

*End of FairGig Agent Specification*
*Version 1.0 | April 2025 | National Hackathon Edition*
