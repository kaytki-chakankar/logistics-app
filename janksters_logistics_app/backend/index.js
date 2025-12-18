const express = require('express');
const cors = require('cors');
const { google } = require('googleapis');
const fs = require('fs');
const path = require('path');
const { parse } = require('json2csv');

const app = express();
const PORT = process.env.PORT || 3000;

app.use(cors());

const auth = new google.auth.GoogleAuth({
  keyFile: "/etc/secrets/jankster-logistics-app-9940db536b1a.json",
  scopes: ['https://www.googleapis.com/auth/spreadsheets'],
});

const sheets = google.sheets({ version: 'v4', auth });

const SPREADSHEET_ID = '1Id2lRQbEzeTJwza9LPYUeSJOhUvfUduTi_inNMeBaS8';
const RANGE = '1/9/2025!A2:C1000';

app.get('/healthz', (req, res) => {
  res.status(200).send('OK');
});

//updates the master attendance json based on a given sheet
app.get('/attendance/update', async (req, res) => {
  const sheetName = req.query.sheet;
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

    // build the attendanceMap of emails and timestamps
    const attendanceMap = new Map();
    rows.forEach(row => {
      const timestamp = row[0];
      const email = row[1]?.trim().toLowerCase();
      const comment = row[2]?.trim();
      if (!email || !timestamp) return;

      if (!attendanceMap.has(email)) attendanceMap.set(email, []);
      attendanceMap.get(email).push({ timestamp, comment });
    });

    // determine the currentSessionDate from first entry timestamp
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

    // check if this session has already been logged
    const alreadyLogged = Object.values(masterData).some(userMeetings =>
      userMeetings.some(meeting => meeting.date === currentSessionDate)
    );

    if (alreadyLogged) {
      return res.status(400).json({ error: `Attendance for ${currentSessionDate} has already been logged.` });
    }

    // get meeting hours for this session from the "hours" sheet
    const hoursSheetResponse = await sheets.spreadsheets.values.get({
      spreadsheetId: SPREADSHEET_ID,
      range: `hours!1:2`,
    });

    const hoursSheetValues = hoursSheetResponse.data.values || [];
    const dateRow = hoursSheetValues[0] || [];
    const hoursRow = hoursSheetValues[1] || [];

    const sessionColIndex = dateRow.findIndex(dateStr => dateStr === currentSessionDate);

    let officialMeetingHours = 0;
    if (sessionColIndex >= 0 && hoursRow[sessionColIndex]) {
      officialMeetingHours = parseFloat(hoursRow[sessionColIndex]);
      if (isNaN(officialMeetingHours)) officialMeetingHours = 0;
    }

    console.log(`Meeting date: ${currentSessionDate}, official meeting hours from "hours" sheet: ${officialMeetingHours}`);
    if (officialMeetingHours === 0) {
      console.warn('Warning: Official meeting hours is zero or missing for this session date.');
    }

    const flaggedEmails = [];

    attendanceMap.forEach((entries, email) => {
  const sorted = entries.sort((a, b) => new Date(a.timestamp) - new Date(b.timestamp));
  const meetings = [];

  // check if the email has exactly two entries
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

    // check for comments
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

        // adjust duration if close to officialMeetingHours ± 0.2h
        if (officialMeetingHours > 0) {
          const diff = durationHours - officialMeetingHours;
          if (Math.abs(diff) <= 0.2) {
            durationHours = officialMeetingHours;
          }
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


    // Mark absentees with 0 hours
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

    fs.writeFileSync(MASTER_JSON_PATH, JSON.stringify(masterData, null, 2));
    console.log(`Updated master attendance for sheet: ${sheetName}`);
    res.json({ message: `Master attendance updated from sheet: ${sheetName}`, flaggedEmails });

  } catch (error) {
    console.error('Error updating master attendance:', error);
    res.status(500).json({ error: 'Unable to update master attendance.' });
  }
});

//returns the flagged emails from the sheet 
app.get('/attendance/flagged', async (req, res) => {
  const sheetName = req.query.sheet; // date string, e.g. "1/9/2025"
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
      // Find the meeting entry for this sheetName (date)
    const meetingForDate = meetings.find(m => {
      if (!m.date || typeof m.date !== "string") return false;

      // normalize - compare only MM/DD/YYYY portion
      const d = m.date.split(" ")[0];  // "1/9/2025"
      return d === sheetName;
    });

      let flagged = false;
      let totalHoursAttended = 0;

      if (meetingForDate.error) {
        flagged = true;
      } else {
        totalHoursAttended = meetingForDate.durationHours || 0;
      }

      results.push({
        email,
        totalHoursAttended,
        flagged,
      });
    });

    res.json({ results });
  } catch (error) {
    console.error('❌ Error fetching flagged attendance:', error);
    res.status(500).json({ error: 'Unable to fetch flagged attendance.' });
  }
});


// get attendance for a single user by email
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

    // check if user is a rookie
    const isRookie = userData.some(entry => entry.rookie === true);

    // filter out the rookie object, keep only actual meetings with date and durationHours
    const meetings = userData.filter(m => m.date && (typeof m.durationHours === 'number' || m.error === true));

    // total meeting hours
    let totalMeetingHours = 83.5;
    if (isRookie) totalMeetingHours -= 3.5;

    // total hours attended
    const totalHoursAttended = meetings.reduce(
      (sum, m) => sum + (typeof m.durationHours === 'number' ? m.durationHours : 0),
      0
    );
    // attendance percentage
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
  console.log(`Backend running`);
});
