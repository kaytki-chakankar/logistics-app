const express = require('express');
const cors = require('cors');
const { google } = require('googleapis');
const fs = require('fs');
const path = require('path');
const { parse } = require('json2csv');
const app = express();

const PORT = process.env.PORT || 3000;

app.use(cors());
app.use(express.json());
app.use(express.static(path.join(__dirname, 'public'))); 

const auth = new google.auth.GoogleAuth({
  keyFile: "/etc/secrets/service_account.json",
  scopes: ['https://www.googleapis.com/auth/spreadsheets'],
});


const sheets = google.sheets({ version: 'v4', auth });

const SPREADSHEET_ID = '1Id2lRQbEzeTJwza9LPYUeSJOhUvfUduTi_inNMeBaS8';
const RANGE = '1/9/2025!A2:C1000';

const TOTAL_HOURS_PATH = path.join(__dirname, 'total_meeting_hours.json');

function getTotalMeetingHours() {
  if (!fs.existsSync(TOTAL_HOURS_PATH)) return 0;
  const data = JSON.parse(fs.readFileSync(TOTAL_HOURS_PATH, 'utf8'));
  return parseFloat(data.totalHours) || 0;
}

function setTotalMeetingHours(hours) {
  fs.writeFileSync(TOTAL_HOURS_PATH, JSON.stringify({ totalHours: hours }, null, 2));
}


app.get('/healthz', (req, res) => {
  res.status(200).send('OK');
});

// updates the master attendance json based on a given sheet
app.get('/attendance/update', async (req, res) => {
  const sheetName = req.query.sheet;
  let meetingHoursInput = parseFloat(req.query.hours); 
  
  if (isNaN(meetingHoursInput)) meetingHoursInput = 0; 
  if (!sheetName) {
    return res.status(400).json({ error: 'Sheet name required as ?sheet=...' });
  }
  const path = require('path');
  const fs = require('fs');

  console.log(`/attendance/update for sheet: "${sheetName}"`);
  const RANGE = `${sheetName}!A2:C1000`;

  const MASTER_JSON_PATH = path.join(__dirname, 'attendance_master.json');
  let masterData = {};

  try {
    if (fs.existsSync(MASTER_JSON_PATH)) {
      const raw = fs.readFileSync(MASTER_JSON_PATH, 'utf8');
      masterData = JSON.parse(raw);
    }

    // get attendance data from the requested sheet
    const response = await sheets.spreadsheets.values.get({
      spreadsheetId: SPREADSHEET_ID,
      range: RANGE,
    });

    const rows = response.data.values || [];
    if (rows.length === 0) {
      return res.status(404).json({ error: 'No data found in the sheet. Check sheet name or content.' });
    }

    const attendanceMap = new Map();
    rows.forEach(row => {
      const timestamp = row[0];
      const email = row[1]?.trim().toLowerCase();
      const comment = row[2]?.trim();
      if (!email || !timestamp) return;

      if (!attendanceMap.has(email)) attendanceMap.set(email, []);
      attendanceMap.get(email).push({ timestamp, comment });
    });

    let currentSessionDate = null;
    for (let [_, entries] of attendanceMap) {
      if (entries.length > 0) {
        const ts = new Date(entries[0].timestamp);
        currentSessionDate = `${ts.getMonth() + 1}/${ts.getDate()}/${ts.getFullYear()}`;
        break;
      }
    }

    if (!currentSessionDate) {
      return res.status(400).json({ error: 'Could not determine session date from entries.' });
    }

    const alreadyLogged = Object.values(masterData).some(userMeetings =>
      userMeetings.some(meeting => meeting.date === currentSessionDate)
    );

    if (alreadyLogged) {
      return res.status(400).json({ error: `Attendance for ${currentSessionDate} has already been logged.` });
    }
    const officialMeetingHours = meetingHoursInput;

    let totalMeetingHours = getTotalMeetingHours();
    totalMeetingHours += officialMeetingHours;
    setTotalMeetingHours(totalMeetingHours);

    console.log(`Meeting date: ${currentSessionDate}, official meeting hours from "hours" sheet: ${officialMeetingHours}`);
    if (officialMeetingHours === 0) {
      console.warn('Warning: Official meeting hours is zero or missing for this session date.');
    }

    const flaggedEmails = [];

    attendanceMap.forEach((entriesArray, emailKey) => {
      const entries = entriesArray;           
      const email = emailKey.toLowerCase();  

      const sorted = entries.sort((a, b) => new Date(a.timestamp) - new Date(b.timestamp));
      const meetings = [];

      if (sorted.length !== 2) {
        flaggedEmails.push(email);
        const ts = sorted[0] ? new Date(sorted[0].timestamp) : new Date();
        const dateOnly = `${ts.getMonth() + 1}/${ts.getDate()}/${ts.getFullYear()}`;
        meetings.push({
          date: dateOnly,
          error: true,
          reason: 'Incorrect number of entries',
        });
      } else {
        const start = sorted[0];
        const end = sorted[1];
        const ts = new Date(start.timestamp);
        const dateOnly = `${ts.getMonth() + 1}/${ts.getDate()}/${ts.getFullYear()}`;

        if (start.comment || end.comment) {
          flaggedEmails.push(email);
          meetings.push({
            date: dateOnly,
            error: true,
            reason: 'Comment present in entry',
          });
        } else {
          const startTime = new Date(start.timestamp);
          const endTime = new Date(end.timestamp);

          if (isNaN(startTime) || isNaN(endTime)) {
            flaggedEmails.push(email);
            meetings.push({
              date: dateOnly,
              error: true,
              reason: 'Invalid timestamps',
            });
          } else {
            let durationMin = Math.abs(endTime - startTime) / (1000 * 60);
            if (140 <= durationMin && durationMin <= 160) durationMin = 150;

            let durationHours = parseFloat((durationMin / 60).toFixed(2));

            if (officialMeetingHours > 0) {
              const diff = durationHours - officialMeetingHours;
              if (Math.abs(diff) <= 0.2) durationHours = officialMeetingHours;
            }

            meetings.push({
              date: dateOnly,
              durationHours,
            });
          }
        }
      }

      if (!masterData[email]) masterData[email] = [];
      masterData[email].push(...meetings);
    });

    const fullRoster = Object.keys(masterData);
    fullRoster.forEach(email => {
      const hasLogged = masterData[email]?.some(m => m.date === currentSessionDate);
      if (!hasLogged) {
        masterData[email].push({
          date: currentSessionDate,
          durationHours: 0
        });
      }
    });
    
    fs.writeFileSync(
      MASTER_JSON_PATH,
      JSON.stringify(masterData, null, 2)
    );

    console.log(`Master file updated for ${currentSessionDate}`);

    return res.json({
      message: `Attendance logged for ${currentSessionDate}`,
      date: currentSessionDate,
      flagged: flaggedEmails,
      success: true
    });

  } catch (error) {
    console.error('Error updating master attendance:', error);
    res.status(500).json({ error: 'Unable to update master attendance.' });
  }
});

// returns the flagged emails from the sheet 
app.get('/attendance/flagged', async (req, res) => {
  const sheetName = req.query.sheet; 
  if (!sheetName) {
    return res.status(400).json({ error: 'Sheet name (date) required as ?sheet=...' });
  }

  try {
    const MASTER_JSON_PATH = path.join(__dirname, 'attendance_master.json');
    if (!fs.existsSync(MASTER_JSON_PATH)) {
      return res.status(500).json({ error: 'Master attendance file not found.' });
    }

    const masterData = JSON.parse(fs.readFileSync(MASTER_JSON_PATH, 'utf8'));
    const results = [];

    Object.entries(masterData).forEach(([email, meetings]) => {
      const meetingForDate = meetings.find(m => {
        if (!m.date || typeof m.date !== "string") return false;
        const d = m.date.split(" ")[0];
        return d === sheetName;
      });

      if (!meetingForDate) return; 

      let flagged = false;
      let totalHoursAttended = 0;

      if (meetingForDate.error) {
        flagged = true;
      } else {
        totalHoursAttended = meetingForDate.durationHours || 0;
      }

      results.push({
        email,
        date: meetingForDate.date,    
        flagged,
        reason: meetingForDate.reason, 
        totalHoursAttended
      });
    });

    res.json({ results });
  } catch (error) {
    console.error('❌ Error fetching flagged attendance:', error);
    res.status(500).json({ error: 'Unable to fetch flagged attendance.' });
  }
});



// get attendance for a single user by email using preseason_master + different hours
app.get('/attendance/preseason/:email', async (req, res) => {
  console.log('HIT /attendance/preseason/:email for:', req.params.email);
  const email = req.params.email?.toLowerCase();
  if (!email) return res.status(400).json({ error: 'Email required' });

  try {
    const masterPath = path.join(__dirname, 'preseason_master.json');
    if (!fs.existsSync(masterPath)) {
      return res.status(500).json({ error: 'Master attendance file not found. Run /attendance/update first.' });
    }

    const masterData = JSON.parse(fs.readFileSync(masterPath, 'utf8'));
    let userData = masterData[email] || [];

    const isRookie = userData.some(entry => entry.rookie === true);
    const meetings = userData.filter(m => m.date && (typeof m.durationHours === 'number' || m.error === true));

    let totalPreseasonMeetingHours = 83.5;
    if (isRookie) totalPreseasonMeetingHours -= 3.5;

    // total hours attended
    const totalHoursAttended = meetings.reduce(
      (sum, m) => sum + (typeof m.durationHours === 'number' ? m.durationHours : 0),
      0
    );
    // attendance percentage
    const attendancePercentage = totalPreseasonMeetingHours > 0
      ? parseFloat(((totalHoursAttended / totalPreseasonMeetingHours) * 100).toFixed(2))
      : 0;

    res.json({
      email,
      meetings,
      totalHoursAttended,
      totalPreseasonMeetingHours,
      attendancePercentage
    });

  } catch (err) {
    console.error('Error fetching attendance percentage:', err);
    res.status(500).json({ error: 'Unable to fetch attendance data.' });
  }
});


// get attendance for a single user by email using attendance_master
app.get('/attendance/:email', async (req, res) => {
  console.log('HIT /attendance/:email for:', req.params.email);
  const email = req.params.email?.toLowerCase();
  if (!email) return res.status(400).json({ error: 'Email required' });

  try {
    const masterPath = path.join(__dirname, 'attendance_master.json');
    if (!fs.existsSync(masterPath)) {
      return res.status(500).json({ error: 'Master attendance file not found. Run /attendance/update first.' });
    }

    const masterData = JSON.parse(fs.readFileSync(masterPath, 'utf8'));
    let userData = masterData[email] || [];

    const meetings = userData.filter(m => m.date && (typeof m.durationHours === 'number' || m.error === true));
    let totalMeetingHours = getTotalMeetingHours();

    const totalHoursAttended = meetings.reduce(
      (sum, m) => sum + (typeof m.durationHours === 'number' ? m.durationHours : 0),
      0
    );

    const attendancePercentage = totalMeetingHours > 0
      ? parseFloat(((totalHoursAttended / totalMeetingHours) * 100).toFixed(2))
      : 0;

    res.json({
      email,
      meetings,
      totalHoursAttended,
      totalMeetingHours,
      attendancePercentage
    });

  } catch (err) {
    console.error('Error fetching attendance percentage:', err);
    res.status(500).json({ error: 'Unable to fetch attendance data.' });
  }
});

app.get('/attendance/master/download', (req, res) => {
  const filePath = path.join(__dirname, 'attendance_master.json');

  if (fs.existsSync(filePath)) {
    res.download(filePath, 'attendance_master.json', err => {
      if (err) {
        console.error('Error sending file:', err);
        res.status(500).send('Error downloading file');
      }
    });
  } else {
    res.status(404).send('Master attendance file not found');
  }
});

// resolves flagged emails after attendance update
app.post("/attendance/resolve", (req, res) => {
  const { email, date, durationHours, reason, keepFlagged } = req.body;

  if (!email || !date) {
    return res.status(400).json({ message: "Missing email or date" });
  }

  function normalizeDate(d) {
    if (!d) return "";
    return d.split(" ")[0];
  }

  try {
    const MASTER_FILE = path.join(__dirname, 'attendance_master.json');
    if (!fs.existsSync(MASTER_FILE)) {
      return res.status(500).json({ message: "Master attendance file not found" });
    }

    const master = JSON.parse(fs.readFileSync(MASTER_FILE, "utf8"));

    if (!master[email]) master[email] = [];

    const entryIndex = master[email].findIndex(
      m => normalizeDate(m.date) === normalizeDate(date)
    );

    if (entryIndex === -1) {
      master[email].push(
        keepFlagged
          ? { date, error: true, reason: reason || "(no reason provided)" }
          : { date, durationHours: parseFloat(durationHours) || 0 }
      );
    } else {
      master[email][entryIndex] = keepFlagged
        ? { date, error: true, reason: reason || "(no reason provided)" }
        : { date, durationHours: parseFloat(durationHours) || 0 };
    }

    fs.writeFileSync(MASTER_FILE, JSON.stringify(master, null, 2));
    console.log(`Resolved entry for ${email} on ${date}`);
    res.json({ message: "Entry updated successfully" });

  } catch (err) {
    console.error("Error updating entry:", err);
    res.status(500).json({ message: "Failed to update entry" });
  }
});


// gets the raw sheet data for requested email
app.get("/attendance/raw/:email", async (req, res) => {
  try {
    const email = req.params.email.toLowerCase();
    const sheetName = req.query.sheet || "Form Responses 1";

    const response = await sheets.spreadsheets.values.get({
      spreadsheetId: SPREADSHEET_ID,
      range: `${sheetName}!A1:Z1000`,
    });

    const values = response.data.values || [];
    if (values.length < 2) {
      return res.status(404).json({ email, message: "No rows found in sheet" });
    }

    const headers = values[0];
    const dataRows = values.slice(1);

    const mappedRows = dataRows.map(row => {
      const obj = {};
      headers.forEach((header, i) => {
        const cleanHeader = header.trim(); 
        obj[cleanHeader] = row[i] ?? ""; 
      });
      return obj;
    });

    const filtered = mappedRows.filter(
      r => (r["Email Address"] || "").toLowerCase() === email
    );

    res.json({
      email,
      sheet: sheetName,
      count: filtered.length,
      results: filtered
    });

  } catch (err) {
    console.error("Error fetching raw sheet data:", err);
    res.status(500).json({ error: "Failed to fetch sheet data" });
  }
});


// changes attendance data based on manual request
app.post("/attendance/manual-update", async (req, res) => {
  try {
    const { email, date, payload } = req.body;

    if (!email || !date || !payload) {
      return res.status(400).json({ error: "Missing email, date, or payload" });
    }

    const normalizedEmail = email.toLowerCase();

    const masterPath = path.join(__dirname, "attendance_master.json");
    let masterData = {};

    if (fs.existsSync(masterPath)) {
      masterData = JSON.parse(fs.readFileSync(masterPath, "utf8"));
    }

    if (!masterData[normalizedEmail]) {
      return res.status(404).json({
        error: "No attendance records found for this email"
      });
    }

    masterData[normalizedEmail] = masterData[normalizedEmail].filter(
      (entry) => entry.date !== date
    );

    masterData[normalizedEmail].push(payload);

    fs.writeFileSync(masterPath, JSON.stringify(masterData, null, 2));

    console.log(
      `Manual attendance update -> ${normalizedEmail} / ${date}`
    );

    return res.json({ success: true });
  } catch (err) {
    console.error("Manual update error:", err);
    return res.status(500).json({ error: "Internal server error" });
  }
});

// get attendance for the full team for both preseason and build season
app.get("/attendance/team/full", (req, res) => {
  try {
    const isPreseason = req.query.isPreseason === "true";

    const MASTER_FILE = isPreseason
      ? path.join(__dirname, "preseason_master.json")
      : path.join(__dirname, "attendance_master.json");

    if (!fs.existsSync(MASTER_FILE)) {
      return res.status(500).json({ message: "Master attendance file not found" });
    }

    const master = JSON.parse(fs.readFileSync(MASTER_FILE, "utf8"));

    const allDates = new Set();
    Object.values(master).forEach(records => {
      records.forEach(r => {
        if (r.date) allDates.add(r.date);
      });
    });

    const sortedDates = Array.from(allDates).sort(
      (a, b) => new Date(a) - new Date(b)
    );

    const team = Object.entries(master).map(([email, records]) => {
      let attendedCount = 0;
      const recordMap = {};

      records.forEach(r => {
        recordMap[r.date] = r;
        if (Number(r.durationHours) > 0 && !r.error) attendedCount++;
      });

      const totalMeetings = sortedDates.length;
      const attendancePercent =
        totalMeetings > 0
          ? Math.round((attendedCount / totalMeetings) * 100)
          : 0;

      const row = sortedDates.map(date => {
        const r = recordMap[date];
        if (!r) return { status: "missing" };
        if (r.error) return { status: "flagged", reason: r.reason };
        return {
          status: Number(r.durationHours) > 0 ? "attended" : "missed",
        };
      });

      return { email, attendancePercent, row };
    });

    res.json({ dates: sortedDates, team });
  } catch (err) {
    console.error(err);
    res.status(500).json({ message: "Failed to load team attendance" });
  }
});









// app.get('/attendance/master', async (req, res) => {
//   console.log('HIT /attendance/master');

//   try {
//     const response = await sheets.spreadsheets.values.get({
//       spreadsheetId: SPREADSHEET_ID,
//       range: RANGE,
//     });

//     const rows = response.data.values || [];
//     const attendanceMap = new Map();

//     rows.forEach(row => {
//       const timestamp = row[0];
//       const email = row[1]?.trim().toLowerCase();
//       const comment = row[2]?.trim();

//       if (!email || !timestamp) return;

//       if (!attendanceMap.has(email)) {
//         attendanceMap.set(email, []);
//       }

//       attendanceMap.get(email).push({
//         timestamp,
//         comment,
//       });
//     });

//     const masterData = {};

//     attendanceMap.forEach((entries, email) => {
//       const sorted = entries.sort((a, b) => new Date(a.timestamp) - new Date(b.timestamp));
//       const meetings = [];

//       for (let i = 0; i < sorted.length; i += 2) {
//         const start = sorted[i];
//         const end = sorted[i + 1];

//         if (!end || start.comment || end.comment) {
//           meetings.push({
//             date: start.timestamp,
//             error: true,
//             reason: 'Missing pair or comment present',
//           });
//           continue;
//         }

//         const startTime = new Date(start.timestamp);
//         const endTime = new Date(end.timestamp);

//         if (isNaN(startTime) || isNaN(endTime)) {
//           meetings.push({
//             date: start.timestamp,
//             error: true,
//             reason: 'Invalid timestamp',
//           });
//           continue;
//         }

//         let durationMin = Math.abs(endTime - startTime) / (1000 * 60);
//         if (140 <= durationMin && durationMin <= 160) durationMin = 150;

//         meetings.push({
//           date: start.timestamp,
//           durationHours: parseFloat((durationMin / 60).toFixed(2)),
//         });
//       }

//       masterData[email] = meetings;
//     });

//     const MASTER_JSON_PATH = path.join(__dirname, 'attendance_master.json');
//     fs.writeFileSync(MASTER_JSON_PATH, JSON.stringify(masterData, null, 2));
//     console.log(JSON.stringify(masterData[email], null, 2)); // log just one email’s data
//     console.log(`Wrote master attendance to ${MASTER_JSON_PATH}`);
//     res.json({ message: 'Master attendance written successfully.', file: MASTER_JSON_PATH });
//   } catch (error) {
//     console.error('Error writing master attendance:', error);
//     res.status(500).json({ error: 'Failed to write master attendance.' });
//   }
// });


app.listen(PORT, () => {
  console.log(`Backend running on port ${PORT}`);
});
