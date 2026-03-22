# 🎮 Ambiora Esports

A full-stack tournament management platform designed to handle esports competitions at scale — from team registration to match results and leaderboards.

Built and deployed for a live college tech event (**AMBIORA**).

---

## 🚀 Overview

Managing esports tournaments manually (paper/Excel) leads to:
- Duplicate entries  
- Unfair team compositions  
- Inconsistent match data  
- No real-time visibility  

**Ambiora Esports** solves this by providing a centralized system with enforced constraints, real-time updates, and automated tournament flow.

---

## ⚙️ Features

### 🧠 Core Functionality
- Tournament lifecycle management (registration → fixtures → results → leaderboard)
- Admin dashboard for managing teams, players, and matches
- Real-time match updates and standings
- Automated fixture & bracket generation
- Leaderboard computation and ranking logic

---

### 🔐 Constraint & Validation System
- One user can join **only one team per game**
- Same user can participate across **multiple games**
- Prevention of duplicate registrations
- Data consistency across all modules

---

### 🛡️ Access Control
- Role-based access:
  - Admin
  - Game Leader
- Scoped permissions for secure operations

---

### 📊 Data Handling
- Structured data models for teams, matches, and tournaments
- Export functionality (CSV / Excel)
- Audit logs for admin actions
- Validation layers to prevent invalid states

---

### 🎨 UI/UX
- Clean and responsive interface
- Optimized for performance and usability
- Designed for both admin control and user interaction

---

## 🧱 Tech Stack

**Frontend:**
- React / Next.js

**Backend:**
- Node.js (API handling)

**Database:**
- MongoDB / Supabase (depending on your implementation)

**Deployment:**
- Vercel

---

## 📈 Impact

- Managed **40+ teams, 4+ games, 45+ players, and 25+ matches**
- Reduced manual effort and errors by **~80–90%** compared to paper-based workflows
- Successfully used in a **live tournament environment**

---

## 🧩 System Design Highlights

- Modular architecture for multi-game scalability  
- Match lifecycle state management (create → update → complete)  
- Constraint-driven backend logic  
- Real-time data consistency across components  

---

## 🛠️ Setup & Installation

```bash
# Clone the repository
git clone https://github.com/your-username/ambiora-esports.git

# Navigate to project
cd ambiora-esports

# Install dependencies
npm install

# Run development server
npm run dev