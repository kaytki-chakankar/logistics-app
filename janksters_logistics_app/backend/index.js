const express = require('express');
const cors = require('cors');
const { google } = require('googleapis');
const fs = require('fs');
const path = require('path');
const { parse } = require('json2csv'); // Make sure you run: npm install json2csv

const app = express();
const PORT = 3000;

app.use(cors());

const auth = new google.auth.GoogleAuth({
  keyFile: 'service-account.json',
  scopes: ['https://www.googleapis.com/auth/spreadsheets'],
});

const sheets = google.sheets({ version: 'v4', auth });

const SPREADSHEET_ID = '1Id2lRQbEzeTJwza9LPYUeSJOhUvfUduTi_inNMeBaS8';
const RANGE = '1/9/2025!A2:C1000';


//updates the master attendance json based on a given sheet
app.get('/attendance/update', async (req, res) => {
  const sheetName = req.query.sheet;
  if (!sheetName) {
    return res.status(400).json({ error: 'Sheet name required as ?sheet=...' });
  }

  console.log(`📥 HIT /attendance/update for sheet: "${sheetName}"`);
  const RANGE = `${sheetName}!A2:C1000`;

  const MASTER_JSON_PATH = path.join(__dirname, 'attendance_master.json');
  let masterData = {};

  try {
    if (fs.existsSync(MASTER_JSON_PATH)) {
      const raw = fs.readFileSync(MASTER_JSON_PATH, 'utf8');
      masterData = JSON.parse(raw);
    }

    const response = await sheets.spreadsheets.values.get({
      spreadsheetId: SPREADSHEET_ID,
      range: RANGE,
    });

    const rows = response.data.values || [];
    console.log(`📊 Rows pulled from sheet: ${rows.length}`);
    console.log('🧾 Sample row data:', rows.slice(0, 3));

    if (rows.length === 0) {
      return res.status(404).json({ error: 'No data found in the sheet. Check sheet name or content.' });
    }

    const attendanceMap = new Map();
    rows.forEach(row => {
      const timestamp = row[0];
      const email = row[1]?.trim().toLowerCase();
      const comment = row[2]?.trim();
      if (!email || !timestamp) return;

      if (!attendanceMap.has(email)) {
        attendanceMap.set(email, []);
      }
      attendanceMap.get(email).push({ timestamp, comment });
    });

    const flaggedEmails = [];
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

    // Process attendees
    attendanceMap.forEach((entries, email) => {
      const sorted = entries.sort((a, b) => new Date(a.timestamp) - new Date(b.timestamp));
      const meetings = [];

      for (let i = 0; i < sorted.length; i += 2) {
        const start = sorted[i];
        const end = sorted[i + 1];
        const ts = new Date(start.timestamp);
        const dateOnly = `${ts.getMonth() + 1}/${ts.getDate()}/${ts.getFullYear()}`;

        if (!end || start.comment || end.comment) {
          flaggedEmails.push(email);
          meetings.push({
            date: dateOnly,
            error: true,
            reason: 'Missing pair or comment',
          });
          continue;
        }

        const startTime = new Date(start.timestamp);
        const endTime = new Date(end.timestamp);

        if (isNaN(startTime) || isNaN(endTime)) {
          flaggedEmails.push(email);
          meetings.push({
            date: dateOnly,
            error: true,
            reason: 'Invalid timestamps',
          });
          continue;
        }

        let durationMin = Math.abs(endTime - startTime) / (1000 * 60);
        if (140 <= durationMin && durationMin <= 160) durationMin = 150;

        meetings.push({
          date: dateOnly,
          durationHours: parseFloat((durationMin / 60).toFixed(2)),
        });
      }

      if (!masterData[email]) masterData[email] = [];
      masterData[email].push(...meetings);
    });

    // 👇 NEW SECTION — mark absentees with 0 hours
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
    console.log(`✅ Updated master attendance for sheet: ${sheetName}`);
    res.json({ message: `Master attendance updated from sheet: ${sheetName}`, flaggedEmails });

  } catch (error) {
    console.error('❌ Error updating master attendance:', error);
    res.status(500).json({ error: 'Unable to update master attendance.' });
  }
});

//returns the flagged emails from the sheet 
app.get('/attendance/flagged', async (req, res) => {
  console.log('HIT /attendance/flagged');
  try {
    const response = await sheets.spreadsheets.values.get({
      spreadsheetId: SPREADSHEET_ID,
      range: RANGE,
    });

    const rows = response.data.values || [];

    const attendanceMap = new Map();

    rows.forEach(row => {
      const email = row[1]?.trim().toLowerCase();
      if (!email) return;

      if (!attendanceMap.has(email)) {
        attendanceMap.set(email, []);
      }
      attendanceMap.get(email).push(row);
    });

    const results = [];

    attendanceMap.forEach((userRows, email) => {
      let flagged = false;
      let totalMinutesAttended = 0;

      if (userRows.length !== 2) {
        flagged = true;
      } else if (userRows.some(row => row[2] && row[2].trim() !== '')) {
        flagged = true;
      }

      if (userRows.length === 2) {
        const [startStr, endStr] = [userRows[0][0], userRows[1][0]];
        const startTime = new Date(startStr);
        const endTime = new Date(endStr);

        if (!isNaN(startTime.getTime()) && !isNaN(endTime.getTime())) {
          const durationMs = Math.abs(endTime - startTime);
          totalMinutesAttended = (durationMs / (1000 * 60));
          if (140 <= totalMinutesAttended && totalMinutesAttended <= 160) {
            totalMinutesAttended = 150;
          }
        } else {
          flagged = true;
        }
      }

      const totalHoursAttended = parseFloat((totalMinutesAttended / 60).toFixed(2));

      results.push({
        email,
        totalHoursAttended,
        flagged,
      });
    });

    // Save to CSV
    const csvFields = ['email', 'totalHoursAttended', 'flagged'];
    const csv = parse(results, { fields: csvFields });
    const outputPath = path.join(__dirname, 'processed_attendance.csv');
    fs.writeFileSync(outputPath, csv);

    console.log(`✅ Wrote attendance to ${outputPath}`);
    res.json({ message: 'Attendance processed and written to CSV.', results });
  } catch (error) {
    console.error('❌ Error processing attendance:', error);
    res.status(500).json({ error: 'Unable to process attendance.' });
  }
});

// Get attendance for a single user by email
// Get attendance stats for one email
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
    const userData = masterData[email] || [];

    // 1️⃣ Find latest meeting date in master JSON
    let latestDate = null;
    for (const meetings of Object.values(masterData)) {
      for (const m of meetings) {
        if (m.date && !m.error) {
          const d = new Date(m.date);
          if (!latestDate || d > latestDate) {
            latestDate = d;
          }
        }
      }
    }
    if (!latestDate) {
      return res.status(400).json({ error: 'No valid meeting dates found in master.' });
    }

    // 2️⃣ Pull the first two rows from your MeetingHours sheet
    const HOURS_RANGE = `hours!1:2`; // <-- adjust "MeetingHours" to your tab name
    const hoursResp = await sheets.spreadsheets.values.get({
      spreadsheetId: SPREADSHEET_ID,
      range: HOURS_RANGE,
    });

    const values = hoursResp.data.values || [];
    const datesRow = values[0] || [];
    const hoursRow = values[1] || [];

    // 3️⃣ Build date-hours pairs from columns
    const hoursData = [];
    for (let col = 0; col < datesRow.length; col++) {
      const dateStr = datesRow[col];
      const hoursVal = parseFloat(hoursRow[col]) || 0;
      if (dateStr) {
        hoursData.push({
          date: dateStr,
          hours: hoursVal
        });
      }
    }

    // 4️⃣ Sum meeting hours up to latest date
    const totalMeetingHours = hoursData.reduce((sum, entry) => {
      const entryDate = new Date(entry.date);
      if (entryDate <= latestDate) {
        return sum + entry.hours;
      }
      return sum;
    }, 0);

    // 5️⃣ Total attended hours for this user
    const totalHoursAttended = userData.reduce(
      (sum, m) => sum + (m.durationHours || 0), 0
    );

    // 6️⃣ Calculate attendance percentage
    const attendancePercentage = totalMeetingHours > 0
      ? parseFloat(((totalHoursAttended / totalMeetingHours) * 100).toFixed(2))
      : 0;

    res.json({
      email,
      meetings: userData,
      totalHoursAttended,
      totalMeetingHours,
      attendancePercentage
    });

  } catch (err) {
    console.error('❌ Error fetching attendance percentage:', err);
    res.status(500).json({ error: 'Unable to fetch attendance data.' });
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
//     console.log(`✅ Wrote master attendance to ${MASTER_JSON_PATH}`);
//     res.json({ message: 'Master attendance written successfully.', file: MASTER_JSON_PATH });
//   } catch (error) {
//     console.error('❌ Error writing master attendance:', error);
//     res.status(500).json({ error: 'Failed to write master attendance.' });
//   }
// });





app.listen(PORT, () => {
  console.log(`🚀 Backend running on http://localhost:${PORT}`);
});
