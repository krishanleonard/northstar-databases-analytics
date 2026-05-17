# SETUP.md — Step-by-step PC instructions

This guide takes you from a fresh PC (Windows / macOS / Linux) to running every notebook and reproducing every figure in the report. Allow ~30–45 minutes the first time, including downloads.

---

## Step 0 — Get the code onto your machine

```bash
# Either clone from GitHub once you've pushed the repo
git clone https://github.com/<your-username>/northstar-databases-analytics.git
cd northstar-databases-analytics

# Or unzip the supplied folder and `cd` into it
unzip northstar_solution.zip
cd northstar_solution
```

You should now have `data/`, `python_scripts/`, `r_scripts/`, `notebooks/`, `sql/`, `figures/` and `report/` visible.

---

## Step 1 — Install Python 3.10 or newer

### Windows
1. Go to <https://www.python.org/downloads/> → click "Download Python 3.x.x".
2. **IMPORTANT:** during install, tick the box "Add python.exe to PATH" before clicking Install.
3. Open Command Prompt and confirm:

   ```bat
   python --version
   pip --version
   ```

### macOS
```bash
# If you have Homebrew (recommended):
brew install python@3.12

# Otherwise download the .pkg installer from python.org
python3 --version
```

### Linux (Ubuntu/Debian)
```bash
sudo apt update && sudo apt install python3 python3-pip python3-venv -y
python3 --version
```

---

## Step 2 — Create a virtual environment and install the Python dependencies

```bash
# Create the venv (one-time)
python -m venv .venv

# Activate it
#  Windows (cmd):
.venv\Scripts\activate.bat
#  Windows (PowerShell):
.venv\Scripts\Activate.ps1
#  macOS / Linux:
source .venv/bin/activate

# Install the packages
pip install --upgrade pip
pip install pandas numpy scipy scikit-learn matplotlib seaborn jupyter notebook \
            pymongo mongomock python-dotenv ipykernel
```

The `mongomock` package is the fall-back driver — it lets the MongoDB notebook run even if you don't install MongoDB locally.

---

## Step 3 — Build the SQLite database

This is the prerequisite for everything else.

```bash
python python_scripts/build_database.py
```

You should see output like:
```
Loading raw CSVs ... done
Building cleaned tables ... done
Creating 13 indexes ... done
Wrote northstar.db (size ≈ 1.4 MB, 18 tables)
```

A file `northstar.db` should now exist in the project root. Confirm it works:

```bash
python -c "import sqlite3; c = sqlite3.connect('northstar.db'); \
           print(c.execute('SELECT COUNT(*) FROM orders').fetchone())"
# Expected: (1250,)
```

---

## Step 4 — Run the Python notebook (Element 1, Part C — 20 marks)

```bash
jupyter notebook
```

Your browser opens. Navigate to `notebooks/02_python_data_processing.ipynb` and click **Cell → Run All**.

Expected outputs:
- Six PNG figures under `notebooks/figures/`
- Cleaned CSVs under `notebooks/clean/`
- A `_summary.json` containing the four headline numbers
- All cells produce output without errors

If any cell errors, the most common cause is a working-directory mismatch. The notebook uses paths relative to itself (`./data/`, `./clean/`). Ensure you launched `jupyter notebook` from the project root.

---

## Step 5 — Set up MongoDB (one of three options)

You only need one of these.

### Option A — Free MongoDB Atlas cloud (recommended; no local install)

1. Go to <https://www.mongodb.com/cloud/atlas/register> and create a free account.
2. Create an "M0 Free" cluster (any region, any name).
3. Under **Database Access**, create a database user with a username and password — **note them down**.
4. Under **Network Access**, click "Add IP Address" → "Allow Access from Anywhere" (0.0.0.0/0). For coursework this is fine; in production you would restrict it.
5. Click **Connect** on your cluster → "Drivers" → "Python" → copy the connection string. It looks like:

   ```
   mongodb+srv://<username>:<password>@cluster0.xxxxx.mongodb.net/?retryWrites=true&w=majority
   ```

6. Set the environment variable so the notebook picks it up:

   ```bash
   # macOS / Linux (one session)
   export MONGO_URI="mongodb+srv://<username>:<password>@cluster0.xxxxx.mongodb.net/"

   # Windows (cmd)
   set MONGO_URI=mongodb+srv://<username>:<password>@cluster0.xxxxx.mongodb.net/

   # Windows (PowerShell)
   $env:MONGO_URI = "mongodb+srv://<username>:<password>@cluster0.xxxxx.mongodb.net/"
   ```

   Or create a `.env` file in the project root with `MONGO_URI=mongodb+srv://...` and `python-dotenv` will pick it up.

### Option B — MongoDB Community Edition installed locally

1. Download from <https://www.mongodb.com/try/download/community> and install.
2. Start the service:
   - **Windows**: it installs as a Windows service and starts automatically.
   - **macOS** (Homebrew): `brew services start mongodb-community`
   - **Linux**: `sudo systemctl start mongod`
3. Confirm it's running:
   ```bash
   mongosh --eval "db.runCommand({ ping: 1 })"
   ```
4. Set:
   ```bash
   export MONGO_URI="mongodb://localhost:27017"
   ```

### Option C — Use mongomock (fall-back, no MongoDB at all)

Do nothing extra. If `MONGO_URI` is unset and a real Mongo connection fails, the notebook automatically uses `mongomock` (an in-memory MongoDB-compatible engine). All CRUD and aggregation pipelines work identically — only `explain()` output differs (real Atlas will show real plan timings).

---

## Step 6 — Run the MongoDB notebook (Element 1, Parts D & E — 30 marks)

```bash
jupyter notebook notebooks/03_mongodb_design.ipynb
```

Click **Cell → Run All**. Expected outputs:
- Confirmation of connection (Atlas / local Mongo / mongomock)
- Three collections built: `customer_cases` (320 docs), `app_sessions` (~530 docs), `delivery_journeys` (950 docs)
- All four CRUD operations succeeding
- All five aggregation pipelines returning data
- Index list printed for each collection
- Selectivity audit and explain()/$indexStats output (illustrative on mongomock, real on Atlas)

---

## Step 7 — Install R and RStudio (for the .Rmd notebook)

### Windows / macOS / Linux
1. Install R: <https://cran.r-project.org/> → pick your OS → install.
2. Install RStudio Desktop (free): <https://posit.co/download/rstudio-desktop/>.

### Open the notebook
1. Launch RStudio.
2. **File → Open File → r_scripts/01_sql_in_r_and_analytics.Rmd**.
3. The first time, RStudio will offer to install the missing packages — click "Install". The required packages are:
   ```r
   install.packages(c("DBI", "RSQLite", "dplyr", "ggplot2", "tidyr",
                      "knitr", "rmarkdown", "scales"))
   ```
4. Click the **Knit** button (top of editor pane). This produces an HTML report containing every code chunk and its output, plus the embedded charts.
5. Alternatively, run cell-by-cell with Ctrl+Enter to step through.

> The `.Rmd` opens `northstar.db` from a path relative to the project root: `../northstar.db`. If you launched RStudio from a different directory, use `setwd("/path/to/northstar_solution")` first.

---

## Step 8 — Open the Word report

`report/NorthStar_Coursework_Report.docx` is the submission-ready version. Open it in Microsoft Word, Google Docs (upload), LibreOffice, or Pages. It contains:
- Title page
- Executive summary with five numbered findings
- Section 1 — Case study analysis
- Sections 2–6 — One section per marking criterion
- Section 7 — Integrated conclusions and recommendations
- Appendix — Repository structure

The figures referenced in the report are embedded inside the docx; you do not need the standalone PNGs to read it.

---

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| `ModuleNotFoundError: pymongo` | Activate the venv (`source .venv/bin/activate` or Windows equivalent), then `pip install pymongo` |
| `sqlite3.OperationalError: no such table: orders` | Re-run `python python_scripts/build_database.py` from the project root |
| `MongoServerSelectionTimeoutError` | Atlas IP whitelist not opened, or wrong username/password — recheck Step 5A |
| RStudio cannot find the database | `setwd("/full/path/to/northstar_solution")` then re-knit |
| Notebook says `mongomock` | That's fine — see Step 5 Option C; results are still correct |
| Figures don't render in Jupyter | `pip install matplotlib seaborn`, restart kernel, re-run |

---

## Time budget at a glance

| Step | First run | Re-run |
|------|-----------|--------|
| Python install + pip | 5–10 min | — |
| Build SQLite database | 5 sec | 5 sec |
| Run 02_python_data_processing.ipynb | 30 sec | 30 sec |
| MongoDB Atlas signup | 5–10 min | — |
| Run 03_mongodb_design.ipynb | 20 sec | 20 sec |
| R + RStudio install | 10 min | — |
| Knit RMarkdown | 1–2 min | 30 sec |

Total cold-start: ~30–45 minutes. After that, every re-run finishes in under 2 minutes end-to-end.
