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
app.use(express.static(path.join(__dirname, 'build/web')));

const auth = new google.auth.GoogleAuth({
  keyFile: "/etc/secrets/service_account.json",
  scopes: ['https://www.googleapis.com/auth/spreadsheets'],
});


const sheets = google.sheets({ version: 'v4', auth });

const SPREADSHEET_ID = '1Id2lRQbEzeTJwza9LPYUeSJOhUvfUduTi_inNMeBaS8';
const RANGE = '1/9/2025!A2:C1000';
const ATTENDANCE_RESPONSE_SHEET = process.env.ATTENDANCE_RESPONSE_SHEET || 'Form Responses 1';

const TOTAL_HOURS_PATH = path.join(__dirname, 'total_meeting_hours.json');
const ATTENDANCE_ADJUSTMENTS_PATH = path.join(__dirname, 'attendance_adjustments.json');
const ATTENDANCE_ADJUSTMENT_SETTINGS_PATH = path.join(__dirname, 'attendance_adjustment_settings.json');
const DEVELOPERS_PATH = path.join(__dirname, 'developer_emails.json');
const DEFAULT_DEVELOPERS = [
  'kchakankar27@ndsj.org',
  'aferrer@ndsj.org',
  'bfarrer@ndsj.org',
  'mcarrillo@ndsj.org',
  'abhardwaj26@ndsj.org',
  'thensley26@ndsj.org',
  'aarjun27@ndsj.org',
];

function getAttendanceAdjustments() {
  if (!fs.existsSync(ATTENDANCE_ADJUSTMENTS_PATH)) return [];
  const data = JSON.parse(fs.readFileSync(ATTENDANCE_ADJUSTMENTS_PATH, 'utf8'));
  return Array.isArray(data) ? data : [];
}

function saveAttendanceAdjustments(adjustments) {
  fs.writeFileSync(
    ATTENDANCE_ADJUSTMENTS_PATH,
    JSON.stringify(adjustments, null, 2)
  );
}

function getAttendanceAdjustmentSettings() {
  if (!fs.existsSync(ATTENDANCE_ADJUSTMENT_SETTINGS_PATH)) return { closedDates: [] };
  const settings = JSON.parse(fs.readFileSync(ATTENDANCE_ADJUSTMENT_SETTINGS_PATH, 'utf8'));
  return {
    closedDates: Array.isArray(settings.closedDates) ? settings.closedDates : [],
  };
}

function saveAttendanceAdjustmentSettings(settings) {
  fs.writeFileSync(
    ATTENDANCE_ADJUSTMENT_SETTINGS_PATH,
    JSON.stringify(settings, null, 2)
  );
}

function getDevelopers() {
  if (!fs.existsSync(DEVELOPERS_PATH)) return [...DEFAULT_DEVELOPERS];
  const data = JSON.parse(fs.readFileSync(DEVELOPERS_PATH, 'utf8'));
  return Array.isArray(data)
    ? [...new Set(data.map(email => String(email).trim().toLowerCase()).filter(Boolean))]
    : [...DEFAULT_DEVELOPERS];
}

function saveDevelopers(developers) {
  fs.writeFileSync(DEVELOPERS_PATH, JSON.stringify(developers, null, 2));
}

function getTotalMeetingHours() {
  if (!fs.existsSync(TOTAL_HOURS_PATH)) return 0;
  const data = JSON.parse(fs.readFileSync(TOTAL_HOURS_PATH, 'utf8'));
  return parseFloat(data.totalHours) || 0;
}

function setTotalMeetingHours(hours) {
  fs.writeFileSync(TOTAL_HOURS_PATH, JSON.stringify({ totalHours: hours }, null, 2));
}

function formatMeetingDate(timestamp) {
  const date = new Date(timestamp);
  if (isNaN(date)) return null;
  return `${date.getMonth() + 1}/${date.getDate()}/${date.getFullYear()}`;
}

function normalizeMeetingDate(value) {
  const match = String(value || '').trim().match(/^(\d{1,2})\/(\d{1,2})\/(\d{4})$/);
  if (!match) return null;
  const month = Number(match[1]);
  const day = Number(match[2]);
  const year = Number(match[3]);
  const date = new Date(year, month - 1, day);
  if (date.getFullYear() !== year || date.getMonth() !== month - 1 || date.getDate() !== day) return null;
  return `${month}/${day}/${year}`;
}


app.get('/healthz', (req, res) => {
  res.status(200).send('OK');
});

// Shared developer access list used by the frontend dashboard.
app.get('/developers', (req, res) => {
  try {
    res.json({ developers: getDevelopers() });
  } catch (err) {
    console.error('Error loading developers:', err);
    res.status(500).json({ error: 'Unable to load developers.' });
  }
});

app.post('/developers', (req, res) => {
  const email = String(req.body?.email || '').trim().toLowerCase();
  if (!/^\S+@\S+\.\S+$/.test(email)) {
    return res.status(400).json({ error: 'Enter a valid email address.' });
  }
  try {
    const developers = getDevelopers();
    if (developers.includes(email)) {
      return res.status(409).json({ error: 'That person is already a developer.' });
    }
    developers.push(email);
    developers.sort();
    saveDevelopers(developers);
    res.status(201).json({ developers });
  } catch (err) {
    console.error('Error adding developer:', err);
    res.status(500).json({ error: 'Unable to add developer.' });
  }
});

app.delete('/developers/:email', (req, res) => {
  const email = decodeURIComponent(req.params.email).trim().toLowerCase();
  try {
    const developers = getDevelopers();
    if (!developers.includes(email)) {
      return res.status(404).json({ error: 'Developer not found.' });
    }
    if (developers.length === 1) {
      return res.status(400).json({ error: 'At least one developer must remain.' });
    }
    const updatedDevelopers = developers.filter(item => item !== email);
    saveDevelopers(updatedDevelopers);
    res.json({ developers: updatedDevelopers });
  } catch (err) {
    console.error('Error removing developer:', err);
    res.status(500).json({ error: 'Unable to remove developer.' });
  }
});

// Lists submitted adjustment requests for the developer dashboard. This must
// stay above /attendance/:email so "adjustments" is not treated as an email.
app.get('/attendance/adjustments', (req, res) => {
  try {
    const adjustments = getAttendanceAdjustments();
    const pendingFirst = adjustments.sort((a, b) => {
      if (a.status === b.status) return (b.submittedAt || '').localeCompare(a.submittedAt || '');
      return a.status === 'pending' ? -1 : 1;
    });
    res.json({ adjustments: pendingFirst });
  } catch (err) {
    console.error('Error reading attendance adjustments:', err);
    res.status(500).json({ error: 'Unable to load attendance adjustments.' });
  }
});

// Dates are open for adjustments by default. This list contains only closed dates.
app.get('/attendance/adjustments/settings', (req, res) => {
  try {
    res.json(getAttendanceAdjustmentSettings());
  } catch (err) {
    console.error('Error reading attendance adjustment settings:', err);
    res.status(500).json({ error: 'Unable to load adjustment settings.' });
  }
});

app.post('/attendance/adjustments/settings', (req, res) => {
  const date = normalizeMeetingDate(req.body?.date);
  const isOpen = req.body?.isOpen;
  if (!date || typeof isOpen !== 'boolean') {
    return res.status(400).json({ error: 'Date and isOpen are required.' });
  }
  try {
    const settings = getAttendanceAdjustmentSettings();
    const closedDates = new Set(settings.closedDates);
    if (isOpen) closedDates.delete(date);
    else closedDates.add(date);
    const updatedSettings = { closedDates: Array.from(closedDates).sort((a, b) => new Date(a) - new Date(b)) };
    saveAttendanceAdjustmentSettings(updatedSettings);
    res.json(updatedSettings);
  } catch (err) {
    console.error('Error saving attendance adjustment settings:', err);
    res.status(500).json({ error: 'Unable to save adjustment settings.' });
  }
});

// Updates master attendance from the shared response sheet for one selected date.
app.get('/attendance/update', async (req, res) => {
  const meetingDate = normalizeMeetingDate(req.query.date);
  let meetingHoursInput = parseFloat(req.query.hours); 
  
  if (isNaN(meetingHoursInput)) meetingHoursInput = 0; 
  if (!meetingDate) {
    return res.status(400).json({ error: 'A valid meeting date is required as ?date=M/D/YYYY.' });
  }
  const path = require('path');
  const fs = require('fs');

  console.log(`/attendance/update for ${meetingDate} in "${ATTENDANCE_RESPONSE_SHEET}"`);
  const RANGE = `${ATTENDANCE_RESPONSE_SHEET}!A2:C1000`;

  const MASTER_JSON_PATH = path.join(__dirname, 'attendance_master.json');
  let masterData = {};

  try {
    if (fs.existsSync(MASTER_JSON_PATH)) {
      const raw = fs.readFileSync(MASTER_JSON_PATH, 'utf8');
      masterData = JSON.parse(raw);
    }

    // Read the shared form-response sheet, then keep only rows for this meeting.
    const response = await sheets.spreadsheets.values.get({
      spreadsheetId: SPREADSHEET_ID,
      range: RANGE,
    });

    const rows = response.data.values || [];
    const rowsForMeeting = rows.filter(row => formatMeetingDate(row[0]) === meetingDate);
    if (rowsForMeeting.length === 0) {
      return res.status(404).json({ error: `No attendance rows found for ${meetingDate} in ${ATTENDANCE_RESPONSE_SHEET}.` });
    }

    const attendanceMap = new Map();
    rowsForMeeting.forEach(row => {
      const timestamp = row[0];
      const email = row[1]?.trim().toLowerCase();
      const comment = row[2]?.trim();
      if (!email || !timestamp) return;

      if (!attendanceMap.has(email)) attendanceMap.set(email, []);
      attendanceMap.get(email).push({ timestamp, comment });
    });

    const currentSessionDate = meetingDate;

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
        const dateOnly = currentSessionDate;
        meetings.push({
          date: dateOnly,
          error: true,
          reason: 'Incorrect number of entries',
        });
      } else {
        const start = sorted[0];
        const end = sorted[1];
        const dateOnly = currentSessionDate;

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
            if (
              officialMeetingHours > 0 &&
              durationHours > officialMeetingHours + 1
            ) {
              flaggedEmails.push(email);
              meetings.push({
                date: dateOnly,
                error: true,
                reason: `Absurd duration: ${durationHours}h for a ${officialMeetingHours}h meeting`
              });
            } else {
              meetings.push({
                date: dateOnly,
                durationHours
              });
            }
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
  const meetingDate = normalizeMeetingDate(req.query.date);
  if (!meetingDate) {
    return res.status(400).json({ error: 'Meeting date required as ?date=M/D/YYYY.' });
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
        return d === meetingDate;
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

    const meetings = userData
      .filter(m => m.date && (typeof m.durationHours === 'number' || m.error === true))
      .sort((a, b) => {
        const aDate = new Date(a.date);
        const bDate = new Date(b.date);
        return aDate - bDate; 
      });   
      
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

app.get('/attendance/total/download', (req, res) => {
  const filePath = path.join(__dirname, 'total_meeting_hours.json');

  if (fs.existsSync(filePath)) {
    res.download(filePath, 'total_meeting_hours.json', err => {
      if (err) {
        console.error('Error sending file:', err);
        res.status(500).send('Error downloading file');
      }
    });
  } else {
    res.status(404).send('total hour file not found');
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
    const sheetName = req.query.sheet || ATTENDANCE_RESPONSE_SHEET;
    const meetingDate = req.query.date ? normalizeMeetingDate(req.query.date) : null;
    if (req.query.date && !meetingDate) {
      return res.status(400).json({ error: 'Date must use M/D/YYYY.' });
    }

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

    const filtered = mappedRows.filter(r =>
      (r["Email Address"] || "").toLowerCase() === email &&
      (!meetingDate || formatMeetingDate(r.Timestamp) === meetingDate)
    );

    res.json({
      email,
      sheet: sheetName,
      date: meetingDate,
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

// Submits a member's request to correct a single day's attendance.
app.post('/attendance/adjustments', (req, res) => {
  const { email, date, arrivalTime, departureTime, hoursHere } = req.body;
  const durationHours = Number(hoursHere);

  if (!email || !date || !arrivalTime || !departureTime || !Number.isFinite(durationHours)) {
    return res.status(400).json({ error: 'Email, date, arrival time, departure time, and hours are required.' });
  }
  if (durationHours < 0 || durationHours > 24) {
    return res.status(400).json({ error: 'Hours must be between 0 and 24.' });
  }

  try {
    const settings = getAttendanceAdjustmentSettings();
    if (settings.closedDates.includes(normalizeMeetingDate(date))) {
      return res.status(403).json({ error: `Adjustments are closed for ${date}.` });
    }
    const adjustments = getAttendanceAdjustments();
    const masterPath = path.join(__dirname, 'attendance_master.json');
    const masterData = fs.existsSync(masterPath)
      ? JSON.parse(fs.readFileSync(masterPath, 'utf8'))
      : {};
    const normalizedEmail = email.trim().toLowerCase();
    const normalizeDate = value => String(value || '').split(' ')[0];
    const previousEntry = (masterData[normalizedEmail] || []).find(
      entry => normalizeDate(entry.date) === normalizeDate(date)
    );
    const previousAttendance = previousEntry?.error
      ? {
          status: 'flagged',
          reason: previousEntry.reason || 'Flagged entry',
        }
      : previousEntry
          ? {
              status: Number(previousEntry.durationHours) > 0 ? 'attended' : 'absent',
              hours: Number(previousEntry.durationHours) || 0,
            }
          : { status: 'missing' };
    const adjustment = {
      id: `${Date.now()}-${Math.random().toString(36).slice(2, 8)}`,
      email: normalizedEmail,
      date: date.trim(),
      arrivalTime: arrivalTime.trim(),
      departureTime: departureTime.trim(),
      hoursHere: Number(durationHours.toFixed(2)),
      previousAttendance,
      status: 'pending',
      submittedAt: new Date().toISOString(),
    };
    adjustments.unshift(adjustment);
    saveAttendanceAdjustments(adjustments);
    res.status(201).json({ adjustment });
  } catch (err) {
    console.error('Error saving attendance adjustment:', err);
    res.status(500).json({ error: 'Unable to save attendance adjustment.' });
  }
});

// Resolves an adjustment. Approving it updates the attendance record for that date.
app.post('/attendance/adjustments/:id/resolve', (req, res) => {
  const { status } = req.body;
  if (status !== 'approved' && status !== 'rejected') {
    return res.status(400).json({ error: 'Status must be approved or rejected.' });
  }

  try {
    const adjustments = getAttendanceAdjustments();
    const adjustment = adjustments.find(item => item.id === req.params.id);
    if (!adjustment) return res.status(404).json({ error: 'Adjustment request not found.' });
    if (adjustment.status !== 'pending') {
      return res.status(400).json({ error: 'This request has already been resolved.' });
    }

    if (status === 'approved') {
      const masterPath = path.join(__dirname, 'attendance_master.json');
      if (!fs.existsSync(masterPath)) {
        return res.status(500).json({ error: 'Master attendance file not found.' });
      }
      const masterData = JSON.parse(fs.readFileSync(masterPath, 'utf8'));
      const email = adjustment.email;
      if (!masterData[email]) masterData[email] = [];

      const normalizeDate = value => String(value || '').split(' ')[0];
      const entryIndex = masterData[email].findIndex(
        entry => normalizeDate(entry.date) === normalizeDate(adjustment.date)
      );
      const updatedEntry = {
        date: adjustment.date,
        durationHours: adjustment.hoursHere,
      };
      if (entryIndex === -1) masterData[email].push(updatedEntry);
      else masterData[email][entryIndex] = updatedEntry;

      fs.writeFileSync(masterPath, JSON.stringify(masterData, null, 2));
    }

    adjustment.status = status;
    adjustment.resolvedAt = new Date().toISOString();
    saveAttendanceAdjustments(adjustments);
    res.json({ adjustment });
  } catch (err) {
    console.error('Error resolving attendance adjustment:', err);
    res.status(500).json({ error: 'Unable to resolve attendance adjustment.' });
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
      return res.status(500).json({
        message: "Master attendance file not found"
      });
    }

    const raw = fs.readFileSync(MASTER_FILE, "utf8");
    if (!raw) {
      return res.status(500).json({
        message: "Master file is empty"
      });
    }

    const master = JSON.parse(raw);

    // normalize date safely (prevents duplicate "fake different dates")
    const normalizeDate = (d) => {
      if (!d) return null;
      const parsed = new Date(d);
      if (isNaN(parsed)) return d;
      return parsed.toISOString().split("T")[0];
    };

    // collect all unique dates safely
    const allDates = new Set();

    Object.values(master).forEach(records => {
      if (!Array.isArray(records)) return;

      records.forEach(r => {
        if (r?.date) {
          allDates.add(normalizeDate(r.date));
        }
      });
    });

    const sortedDates = Array.from(allDates).sort(
      (a, b) => new Date(a) - new Date(b)
    );

    // total meeting hours
    let totalMeetingHours = 0;

    if (isPreseason) {
      totalMeetingHours = 83.5;
    } else {
      try {
        if (fs.existsSync(TOTAL_HOURS_PATH)) {
          const rawHours = fs.readFileSync(TOTAL_HOURS_PATH, "utf8");
          if (rawHours) {
            const parsed = JSON.parse(rawHours);
            totalMeetingHours = parseFloat(parsed.totalHours) || 0;
          }
        }
      } catch (err) {
        console.error("Error reading total hours:", err);
        totalMeetingHours = 0;
      }
    }

    const team = Object.entries(master).map(([email, records]) => {
      if (!Array.isArray(records)) {
        return {
          email,
          attendancePercent: 0,
          attendedHours: 0,
          row: []
        };
      }

      let attendedHours = 0;

      // FIX: prevent duplicate date overwrite bugs
      const recordMap = new Map();

      records.forEach(r => {
        if (!r?.date) return;

        const dateKey = normalizeDate(r.date);

        // keep ONLY latest entry per date
        recordMap.set(dateKey, r);

        if (r.error) return;

        const hours = Number(r.durationHours);
        if (!isNaN(hours) && hours > 0) {
          attendedHours += hours;
        }
      });

      const attendancePercent =
        totalMeetingHours > 0
          ? Math.round((attendedHours / totalMeetingHours) * 100)
          : 0;

      const row = sortedDates.map(date => {
        const r = recordMap.get(date);

        if (!r) {
          return { status: "missing", hours: 0 };
        }

        if (r.error) {
          return {
            status: "flagged",
            reason: r.reason || "flagged",
            hours: 0
          };
        }

        const hours = Number(r.durationHours) || 0;

        return {
          status: hours > 0 ? "attended" : "missed",
          hours
        };
      });

      return {
        email,
        attendancePercent,
        attendedHours,
        row
      };
    });

    // FINAL SAFETY: remove any accidental duplicate emails
    const uniqueTeamMap = new Map();
    team.forEach(t => uniqueTeamMap.set(t.email, t));

    res.json({
      dates: sortedDates,
      totalMeetingHours,
      team: Array.from(uniqueTeamMap.values())
    });

  } catch (err) {
    console.error("FULL ERROR:", err);

    res.status(500).json({
      message: "Failed to load team attendance",
      error: err.message
    });
  }
});

app.get('/total-hours', (req, res) => {
  try {
    const MASTER_JSON_PATH = path.join(__dirname, 'attendance_master.json');

    if (!fs.existsSync(MASTER_JSON_PATH)) {
      return res.status(404).json({ error: 'Master attendance file not found' });
    }

    const raw = fs.readFileSync(MASTER_JSON_PATH, 'utf8');
    const attendanceData = JSON.parse(raw);

    let total = 0;

    Object.values(attendanceData).forEach(records => {
      records.forEach(entry => {
        if (
          typeof entry.durationHours === 'number' &&
          !entry.error
        ) {
          total += entry.durationHours;
        }
      });
    });

    res.json({ totalHours: parseFloat(total.toFixed(2)) });

  } catch (err) {
    console.error('Total hours calculation error:', err);
    res.status(500).json({ error: 'Failed to calculate total hours' });
  }
});


app.get("/attendance/team/hours", (req, res) => {
  try {
    const masterPath = path.join(__dirname, "attendance_master.json");

    if (!fs.existsSync(masterPath)) {
      return res.status(500).json({
        error: "Master attendance file not found."
      });
    }

    const masterData = JSON.parse(
      fs.readFileSync(masterPath, "utf8")
    );

    const results = Object.entries(masterData).map(([email, meetings]) => {
      const totalHoursAttended = meetings.reduce((sum, meeting) => {
        return sum + (
          typeof meeting.durationHours === "number"
            ? meeting.durationHours
            : 0
        );
      }, 0);

      return {
        email,
        totalHoursAttended: Number(totalHoursAttended.toFixed(2))
      };
    });

    results.sort(
      (a, b) => b.totalHoursAttended - a.totalHoursAttended
    );

    res.json({
      count: results.length,
      results
    });

  } catch (err) {
    console.error("Error calculating team hours:", err);
    res.status(500).json({
      error: "Unable to calculate team hours."
    });
  }
});


app.get('/', (req, res) => {
  res.send('backend is running');
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
