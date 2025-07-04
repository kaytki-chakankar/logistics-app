const express = require('express');
const cors = require('cors');
const { google } = require('googleapis');
const app = express();
const PORT = 3000;

app.use(cors());

const auth = new google.auth.GoogleAuth({
  keyFile: 'service-account.json',
  scopes: ['https://www.googleapis.com/auth/spreadsheets.readonly'],
});

const sheets = google.sheets({ version: 'v4', auth });

const SPREADSHEET_ID = '1p9AiNeGf1y_S-5nVXhgn0R0VuGeOdv_jIrsju1WmhNg';
const RANGE = 'Form Responses 1!A2:C1000';

app.get('/attendance/:email', async (req, res) => {
  let { email } = req.params;
  //email = "abhardwaj27@ndsj.org";

  try {
    const response = await sheets.spreadsheets.values.get({
      spreadsheetId: SPREADSHEET_ID,
      range: RANGE,
    });

    const rows = response.data.values || [];
    const userRows = rows.filter(row => row[1]?.trim().toLowerCase() === email.toLowerCase());

    if (userRows.length !== 2) {
      return res.json({ email, attendanceCount: userRows.length, flagged: true });
    }

    if (userRows.some(row => row[2] && row[2].trim() !== '')) {
      return res.json({ email, attendanceCount: 2, flagged: true });
    }

    const [startStr, endStr] = [userRows[0][0], userRows[1][0]];
    const startTime = new Date(startStr);
    const endTime = new Date(endStr);

    if (isNaN(startTime.getTime()) || isNaN(endTime.getTime())) {
      return res.status(400).json({ error: 'Invalid date format in sheet.' });
    }

    const durationMs = Math.abs(endTime - startTime);
    const totalMinutesAttended = Math.round(durationMs / (1000 * 60));

    return res.json({ email, totalMinutesAttended });
  } catch (error) {
    console.error(error);
    return res.status(500).json({ error: 'Unable to fetch attendance.' });
  }
});

app.listen(PORT, () => {
  console.log(`Backend running on http://localhost:${PORT}`);
});
