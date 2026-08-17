const express = require('express');
const cors = require('cors');
const { google } = require('googleapis');
const admin = require('firebase-admin');
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
const ATTENDANCE_RESPONSE_SHEET = process.env.ATTENDANCE_RESPONSE_SHEET || 'Form Responses 1';

const TOTAL_HOURS_PATH = path.join(__dirname, 'total_meeting_hours.json');
const DEFAULT_FULL_SEMESTER_HOURS = 235;
const DEFAULT_DEVELOPERS = [
  'kchakankar27@ndsj.org',
  'aferrer@ndsj.org',
  'bfarrer@ndsj.org',
  'mcarrillo@ndsj.org',
  'abhardwaj26@ndsj.org',
  'thensley26@ndsj.org',
  'aarjun27@ndsj.org',
];
const DEFAULT_LINKS = [
  {
    title: 'Leadership Drive',
    url: 'https://drive.google.com/drive/folders/0ANydg9_JDsrrUk9PVA',
  },
  {
    title: 'Team Calendar',
    url: 'https://docs.google.com/spreadsheets/d/1VH-h4vqi3WZ0dV_-8Qf2T6R2lpBFExDJWNmpr447Zds/edit?gid=0#gid=0',
  },
  {
    title: 'Team Resource Website',
    url: 'https://sites.google.com/ndsj.org/jankster-resources/home',
  },
];

let firestore;

function getFirestore() {
  if (firestore) return firestore;
  const serviceAccountPath = process.env.FIREBASE_SERVICE_ACCOUNT_PATH || '/etc/secrets/service_account.json';
  if (!fs.existsSync(serviceAccountPath)) {
    throw new Error(`Firestore service account was not found at ${serviceAccountPath}.`);
  }
  if (!admin.apps.length) {
    admin.initializeApp({
      credential: admin.credential.cert(JSON.parse(fs.readFileSync(serviceAccountPath, 'utf8'))),
    });
  }
  firestore = admin.firestore();
  return firestore;
}

function settingsDocument() {
  return getFirestore().collection('logisticsApp').doc('settings');
}

async function getDevelopers() {
  const snapshot = await settingsDocument().get();
  const developers = snapshot.get('developers');
  return Array.isArray(developers) && developers.length > 0
    ? [...new Set(developers.map(email => String(email).trim().toLowerCase()).filter(Boolean))]
    : [...DEFAULT_DEVELOPERS];
}

async function saveDevelopers(developers) {
  await settingsDocument().set({ developers }, { merge: true });
}

async function getMembers() {
  const snapshot = await settingsDocument().get();
  const members = snapshot.get('members');
  if (Array.isArray(members)) {
    return [...new Set(members.map(email => String(email).trim().toLowerCase()).filter(Boolean))];
  }

  // One-time roster migration: preserve the existing team from attendance data.
  const migratedMembers = Object.keys(await getBuildAttendanceMaster()).sort();
  await saveMembers(migratedMembers);
  return migratedMembers;
}

async function saveMembers(members) {
  await settingsDocument().set({ members }, { merge: true });
}

function normalizeLink(link) {
  const title = String(link?.title || '').trim();
  const url = String(link?.url || '').trim();
  try {
    const parsedUrl = new URL(url);
    if (!title || !['http:', 'https:'].includes(parsedUrl.protocol)) return null;
    return { title, url: parsedUrl.toString() };
  } catch (_) {
    return null;
  }
}

async function getImportantLinks() {
  const snapshot = await settingsDocument().get();
  const links = snapshot.get('importantLinks');
  if (Array.isArray(links)) {
    return links.map(normalizeLink).filter(Boolean);
  }

  // Preserve the existing bundled links as the one-time initial list.
  await settingsDocument().set({ importantLinks: DEFAULT_LINKS }, { merge: true });
  return DEFAULT_LINKS;
}

async function saveImportantLinks(links) {
  await settingsDocument().set({ importantLinks: links }, { merge: true });
}

async function getAttendanceAdjustmentSettings() {
  const snapshot = await settingsDocument().get();
  const closedDates = snapshot.get('closedAdjustmentDates');
  return { closedDates: Array.isArray(closedDates) ? closedDates : [] };
}

async function saveAttendanceAdjustmentSettings(settings) {
  await settingsDocument().set(
    { closedAdjustmentDates: settings.closedDates },
    { merge: true }
  );
}

async function getAttendanceAdjustments() {
  const snapshot = await getFirestore().collection('attendanceAdjustments').get();
  return snapshot.docs.map(document => ({ id: document.id, ...document.data() }));
}

async function saveAttendanceAdjustment(adjustment) {
  await getFirestore().collection('attendanceAdjustments').doc(adjustment.id).set(adjustment);
}

function buildAttendanceCollection() {
  return getFirestore().collection('buildAttendance');
}

function buildAttendanceMetaDocument() {
  return getFirestore().collection('logisticsApp').doc('buildAttendanceMeta');
}

async function saveBuildAttendanceMaster(master) {
  const entries = Object.entries(master);
  for (let start = 0; start < entries.length; start += 450) {
    const batch = getFirestore().batch();
    entries.slice(start, start + 450).forEach(([email, meetings]) => {
      batch.set(buildAttendanceCollection().doc(email), { meetings });
    });
    await batch.commit();
  }
  await buildAttendanceMetaDocument().set({ initialized: true }, { merge: true });
}

async function getBuildAttendanceMaster() {
  const snapshot = await buildAttendanceCollection().get();
  if (!snapshot.empty) {
    const master = {};
    snapshot.forEach(document => {
      master[document.id] = Array.isArray(document.get('meetings')) ? document.get('meetings') : [];
    });
    return master;
  }

  // Once this store has been initialized, an empty collection is intentional
  // (for example, after the last member is removed), not a reason to restore
  // the repository copy.
  const meta = await buildAttendanceMetaDocument().get();
  if (meta.get('initialized') === true) return {};

  // One-time migration: seed Firestore from the repository JSON only when
  // Firestore has no attendance records yet. Future deploys never overwrite it.
  const legacyMasterPath = path.join(__dirname, 'attendance_master.json');
  const legacyMaster = fs.existsSync(legacyMasterPath)
    ? JSON.parse(fs.readFileSync(legacyMasterPath, 'utf8'))
    : {};
  if (Object.keys(legacyMaster).length > 0) {
    await saveBuildAttendanceMaster(legacyMaster);
  }
  return legacyMaster;
}

async function createBuildAttendanceMember(email) {
  await buildAttendanceCollection().doc(email).set({ meetings: [] });
  await buildAttendanceMetaDocument().set({ initialized: true }, { merge: true });
}

async function deleteBuildAttendanceMember(email) {
  await buildAttendanceCollection().doc(email).delete();
  await buildAttendanceMetaDocument().set({ initialized: true }, { merge: true });
}

async function saveBuildAttendanceMember(email, meetings) {
  await buildAttendanceCollection().doc(email).set({ meetings });
  await buildAttendanceMetaDocument().set({ initialized: true }, { merge: true });
}

function attendanceSeasonsCollection() {
  return getFirestore().collection('attendanceSeasons');
}

async function getArchivedAttendanceSeasons() {
  const snapshot = await attendanceSeasonsCollection().orderBy('archivedAt', 'desc').get();
  return snapshot.docs.map(document => ({ id: document.id, ...document.data() }));
}

async function getArchivedAttendanceSeason(id) {
  const seasonDocument = await attendanceSeasonsCollection().doc(id).get();
  if (!seasonDocument.exists) return null;
  const records = {};
  const memberDocuments = await seasonDocument.ref.collection('members').get();
  memberDocuments.forEach(document => {
    records[document.id] = Array.isArray(document.get('meetings')) ? document.get('meetings') : [];
  });
  return { id: seasonDocument.id, ...seasonDocument.data(), records };
}

async function resetBuildAttendanceForMembers(members) {
  const existingDocuments = await buildAttendanceCollection().listDocuments();
  for (let start = 0; start < existingDocuments.length; start += 450) {
    const batch = getFirestore().batch();
    existingDocuments.slice(start, start + 450).forEach(document => batch.delete(document));
    await batch.commit();
  }
  for (let start = 0; start < members.length; start += 450) {
    const batch = getFirestore().batch();
    members.slice(start, start + 450).forEach(email => {
      batch.set(buildAttendanceCollection().doc(email), { meetings: [] });
    });
    await batch.commit();
  }
  await buildAttendanceMetaDocument().set(
    { initialized: true, totalMeetingHours: 0 },
    { merge: true }
  );
}

async function archiveAndResetBuildAttendance(name) {
  const normalizedName = String(name || '').trim();
  if (!normalizedName) throw new Error('A season name is required.');

  const existingSeasons = await getArchivedAttendanceSeasons();
  if (existingSeasons.some(season => String(season.name).toLowerCase() === normalizedName.toLowerCase())) {
    throw new Error('A saved season already has that name.');
  }

  const [master, totalMeetingHours, fullSemesterRequiredHours, members] = await Promise.all([
    getBuildAttendanceMaster(),
    getTotalMeetingHours(),
    getFullSemesterRequiredHours(),
    getMembers(),
  ]);
  const seasonDocument = attendanceSeasonsCollection().doc();
  const archivedAt = new Date().toISOString();
  await seasonDocument.set({
    name: normalizedName,
    type: 'build',
    totalMeetingHours,
    fullSemesterRequiredHours,
    archivedAt,
  });

  const entries = Object.entries(master);
  for (let start = 0; start < entries.length; start += 450) {
    const batch = getFirestore().batch();
    entries.slice(start, start + 450).forEach(([email, meetings]) => {
      batch.set(seasonDocument.collection('members').doc(email), { meetings });
    });
    await batch.commit();
  }

  const calendarDocuments = await attendanceCalendarCollection().listDocuments();
  const calendarSnapshots = await Promise.all(calendarDocuments.map(document => document.get()));
  for (let start = 0; start < calendarSnapshots.length; start += 450) {
    const batch = getFirestore().batch();
    calendarSnapshots.slice(start, start + 450).forEach(snapshot => {
      batch.set(seasonDocument.collection('calendar').doc(snapshot.id), snapshot.data());
      batch.delete(snapshot.ref);
    });
    await batch.commit();
  }

  await resetBuildAttendanceForMembers(members);
  return { id: seasonDocument.id, name: normalizedName, type: 'build', totalMeetingHours, fullSemesterRequiredHours, archivedAt };
}

function preseasonAttendanceCollection() {
  return getFirestore().collection('preseasonAttendance');
}

function preseasonAttendanceMetaDocument() {
  return getFirestore().collection('logisticsApp').doc('preseasonAttendanceMeta');
}

async function savePreseasonAttendanceMaster(master) {
  const entries = Object.entries(master);
  for (let start = 0; start < entries.length; start += 450) {
    const batch = getFirestore().batch();
    entries.slice(start, start + 450).forEach(([email, meetings]) => {
      batch.set(preseasonAttendanceCollection().doc(email), { meetings });
    });
    await batch.commit();
  }
  await preseasonAttendanceMetaDocument().set({ initialized: true }, { merge: true });
}

async function getPreseasonAttendanceMaster() {
  const snapshot = await preseasonAttendanceCollection().get();
  if (!snapshot.empty) {
    const master = {};
    snapshot.forEach(document => {
      master[document.id] = Array.isArray(document.get('meetings')) ? document.get('meetings') : [];
    });
    return master;
  }

  const meta = await preseasonAttendanceMetaDocument().get();
  if (meta.get('initialized') === true) return {};

  const legacyMasterPath = path.join(__dirname, 'preseason_master.json');
  const legacyMaster = fs.existsSync(legacyMasterPath)
    ? JSON.parse(fs.readFileSync(legacyMasterPath, 'utf8'))
    : {};
  if (Object.keys(legacyMaster).length > 0) {
    await savePreseasonAttendanceMaster(legacyMaster);
  } else {
    await preseasonAttendanceMetaDocument().set({ initialized: true }, { merge: true });
  }
  return legacyMaster;
}

async function ensureLegacyPreseasonHistory() {
  const settings = await settingsDocument().get();
  if (settings.get('legacyPreseasonHistoryArchived') === true) return;
  const master = await getPreseasonAttendanceMaster();
  const seasonDocument = attendanceSeasonsCollection().doc();
  await seasonDocument.set({
    name: 'Preseason 2025',
    type: 'preseason',
    totalMeetingHours: 83.5,
    archivedAt: new Date().toISOString(),
  });
  const entries = Object.entries(master);
  for (let start = 0; start < entries.length; start += 450) {
    const batch = getFirestore().batch();
    entries.slice(start, start + 450).forEach(([email, meetings]) => {
      batch.set(seasonDocument.collection('members').doc(email), { meetings });
    });
    await batch.commit();
  }
  await settingsDocument().set({ legacyPreseasonHistoryArchived: true }, { merge: true });
}

async function createPreseasonAttendanceMember(email, isRookie) {
  await preseasonAttendanceCollection().doc(email).set({
    meetings: isRookie ? [{ rookie: true }] : [],
  });
  await preseasonAttendanceMetaDocument().set({ initialized: true }, { merge: true });
}

async function setMemberRookieStatus(email, isRookie) {
  const document = await preseasonAttendanceCollection().doc(email).get();
  const meetings = document.exists && Array.isArray(document.get('meetings'))
    ? document.get('meetings').filter(entry => entry?.rookie !== true)
    : [];
  const updatedMeetings = isRookie ? [{ rookie: true }, ...meetings] : meetings;
  await preseasonAttendanceCollection().doc(email).set({ meetings: updatedMeetings });
  await preseasonAttendanceMetaDocument().set({ initialized: true }, { merge: true });
}

async function deletePreseasonAttendanceMember(email) {
  await preseasonAttendanceCollection().doc(email).delete();
  await preseasonAttendanceMetaDocument().set({ initialized: true }, { merge: true });
}

function attendanceCalendarCollection() {
  return getFirestore().collection('attendanceCalendar');
}

function normalizeCalendarMeeting(document) {
  const data = document.data();
  return {
    id: document.id,
    title: data.title || 'Meeting',
    date: data.date,
    startTime: data.startTime || '',
    endTime: data.endTime || '',
    totalHours: Number(data.totalHours) || 0,
    notes: data.notes || '',
    published: data.published === true,
    createdAt: data.createdAt || '',
  };
}

async function getCalendarMeetings({ publishedOnly = false } = {}) {
  const snapshot = await attendanceCalendarCollection().get();
  return snapshot.docs
    .map(normalizeCalendarMeeting)
    .filter(meeting => !publishedOnly || meeting.published)
    .sort((a, b) => new Date(a.date) - new Date(b.date));
}

async function getTotalMeetingHours() {
  const snapshot = await buildAttendanceMetaDocument().get();
  const storedHours = Number(snapshot.get('totalMeetingHours'));
  if (Number.isFinite(storedHours)) return storedHours;

  const legacyHours = fs.existsSync(TOTAL_HOURS_PATH)
    ? Number(JSON.parse(fs.readFileSync(TOTAL_HOURS_PATH, 'utf8')).totalHours) || 0
    : 0;
  await setTotalMeetingHours(legacyHours);
  return legacyHours;
}

async function setTotalMeetingHours(hours) {
  await buildAttendanceMetaDocument().set(
    { totalMeetingHours: Number(hours) || 0 },
    { merge: true }
  );
}

async function getFullSemesterRequiredHours() {
  const snapshot = await buildAttendanceMetaDocument().get();
  const storedHours = Number(snapshot.get('fullSemesterRequiredHours'));
  if (Number.isFinite(storedHours) && storedHours > 0) return storedHours;
  await setFullSemesterRequiredHours(DEFAULT_FULL_SEMESTER_HOURS);
  return DEFAULT_FULL_SEMESTER_HOURS;
}

async function setFullSemesterRequiredHours(hours) {
  await buildAttendanceMetaDocument().set(
    { fullSemesterRequiredHours: Number(hours) },
    { merge: true }
  );
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
app.get('/developers', async (req, res) => {
  try {
    res.json({ developers: await getDevelopers() });
  } catch (err) {
    console.error('Error loading developers:', err);
    res.status(500).json({ error: 'Unable to load developers.' });
  }
});

app.post('/developers', async (req, res) => {
  const email = String(req.body?.email || '').trim().toLowerCase();
  if (!/^\S+@\S+\.\S+$/.test(email)) {
    return res.status(400).json({ error: 'Enter a valid email address.' });
  }
  try {
    const developers = await getDevelopers();
    if (developers.includes(email)) {
      return res.status(409).json({ error: 'That person is already a developer.' });
    }
    developers.push(email);
    developers.sort();
    await saveDevelopers(developers);
    res.status(201).json({ developers });
  } catch (err) {
    console.error('Error adding developer:', err);
    res.status(500).json({ error: 'Unable to add developer.' });
  }
});

app.delete('/developers/:email', async (req, res) => {
  const email = decodeURIComponent(req.params.email).trim().toLowerCase();
  try {
    const developers = await getDevelopers();
    if (!developers.includes(email)) {
      return res.status(404).json({ error: 'Developer not found.' });
    }
    if (developers.length === 1) {
      return res.status(400).json({ error: 'At least one developer must remain.' });
    }
    const updatedDevelopers = developers.filter(item => item !== email);
    await saveDevelopers(updatedDevelopers);
    res.json({ developers: updatedDevelopers });
  } catch (err) {
    console.error('Error removing developer:', err);
    res.status(500).json({ error: 'Unable to remove developer.' });
  }
});

app.get('/important-links', async (req, res) => {
  try {
    res.json({ links: await getImportantLinks() });
  } catch (err) {
    console.error('Error loading important links:', err);
    res.status(500).json({ error: 'Unable to load important links.' });
  }
});

app.post('/important-links', async (req, res) => {
  const link = normalizeLink(req.body);
  if (!link) {
    return res.status(400).json({ error: 'Enter a title and a valid http or https URL.' });
  }
  try {
    const links = await getImportantLinks();
    if (links.some(item => item.url === link.url)) {
      return res.status(409).json({ error: 'That link is already listed.' });
    }
    links.push(link);
    await saveImportantLinks(links);
    res.status(201).json({ links });
  } catch (err) {
    console.error('Error adding important link:', err);
    res.status(500).json({ error: 'Unable to add important link.' });
  }
});

app.delete('/important-links/:index', async (req, res) => {
  const index = Number.parseInt(req.params.index, 10);
  try {
    const links = await getImportantLinks();
    if (!Number.isInteger(index) || index < 0 || index >= links.length) {
      return res.status(404).json({ error: 'Link not found.' });
    }
    const [removed] = links.splice(index, 1);
    await saveImportantLinks(links);
    res.json({ removed, links });
  } catch (err) {
    console.error('Error removing important link:', err);
    res.status(500).json({ error: 'Unable to remove important link.' });
  }
});

// Active members determine who receives new attendance records.
app.get('/members', async (req, res) => {
  try {
    const [members, developers, preseasonMaster] = await Promise.all([
      getMembers(),
      getDevelopers(),
      getPreseasonAttendanceMaster(),
    ]);
    res.json({
      members: members
        .filter(email => !developers.includes(email))
        .map(email => ({
          email,
          rookie: (preseasonMaster[email] || []).some(entry => entry?.rookie === true),
        })),
    });
  } catch (err) {
    console.error('Error loading members:', err);
    res.status(500).json({ error: 'Unable to load members.' });
  }
});

app.post('/members', async (req, res) => {
  const email = String(req.body?.email || '').trim().toLowerCase();
  const rookie = req.body?.rookie === true;
  if (!/^\S+@\S+\.\S+$/.test(email)) {
    return res.status(400).json({ error: 'Enter a valid email address.' });
  }
  try {
    const members = await getMembers();
    if (members.includes(email)) {
      return res.status(409).json({ error: 'That person is already a member.' });
    }
    members.push(email);
    members.sort();
    await saveMembers(members);
    await Promise.all([
      createBuildAttendanceMember(email),
      createPreseasonAttendanceMember(email, rookie),
    ]);
    res.status(201).json({ member: { email, rookie } });
  } catch (err) {
    console.error('Error adding member:', err);
    res.status(500).json({ error: 'Unable to add member.' });
  }
});

app.delete('/members/:email', async (req, res) => {
  const email = decodeURIComponent(req.params.email).trim().toLowerCase();
  try {
    const members = await getMembers();
    if (!members.includes(email)) {
      return res.status(404).json({ error: 'Member not found.' });
    }
    const updatedMembers = members.filter(item => item !== email);
    await saveMembers(updatedMembers);
    await Promise.all([
      deleteBuildAttendanceMember(email),
      deletePreseasonAttendanceMember(email),
    ]);
    res.json({ deleted: email });
  } catch (err) {
    console.error('Error removing member:', err);
    res.status(500).json({ error: 'Unable to remove member.' });
  }
});

app.put('/members/:email/rookie', async (req, res) => {
  const email = decodeURIComponent(req.params.email).trim().toLowerCase();
  const rookie = req.body?.rookie;
  if (typeof rookie !== 'boolean') {
    return res.status(400).json({ error: 'Rookie status is required.' });
  }
  try {
    const members = await getMembers();
    if (!members.includes(email)) {
      return res.status(404).json({ error: 'Member not found.' });
    }
    await setMemberRookieStatus(email, rookie);
    res.json({ member: { email, rookie } });
  } catch (err) {
    console.error('Error updating rookie status:', err);
    res.status(500).json({ error: 'Unable to update rookie status.' });
  }
});

// Lists submitted adjustment requests for the developer dashboard. This must
// stay above /attendance/:email so "adjustments" is not treated as an email.
app.get('/attendance/adjustments', async (req, res) => {
  try {
    const adjustments = await getAttendanceAdjustments();
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
app.get('/attendance/adjustments/settings', async (req, res) => {
  try {
    res.json(await getAttendanceAdjustmentSettings());
  } catch (err) {
    console.error('Error reading attendance adjustment settings:', err);
    res.status(500).json({ error: 'Unable to load adjustment settings.' });
  }
});

app.post('/attendance/adjustments/settings', async (req, res) => {
  const date = normalizeMeetingDate(req.body?.date);
  const isOpen = req.body?.isOpen;
  if (!date || typeof isOpen !== 'boolean') {
    return res.status(400).json({ error: 'Date and isOpen are required.' });
  }
  try {
    const settings = await getAttendanceAdjustmentSettings();
    const closedDates = new Set(settings.closedDates);
    if (isOpen) closedDates.delete(date);
    else closedDates.add(date);
    const updatedSettings = { closedDates: Array.from(closedDates).sort((a, b) => new Date(a) - new Date(b)) };
    await saveAttendanceAdjustmentSettings(updatedSettings);
    res.json(updatedSettings);
  } catch (err) {
    console.error('Error saving attendance adjustment settings:', err);
    res.status(500).json({ error: 'Unable to save adjustment settings.' });
  }
});

app.get('/attendance/settings/full-semester-hours', async (req, res) => {
  try {
    res.json({ fullSemesterRequiredHours: await getFullSemesterRequiredHours() });
  } catch (err) {
    console.error('Error loading full-semester requirement:', err);
    res.status(500).json({ error: 'Unable to load full-semester requirement.' });
  }
});

app.put('/attendance/settings/full-semester-hours', async (req, res) => {
  const hours = Number(req.body?.fullSemesterRequiredHours);
  if (!Number.isFinite(hours) || hours <= 0) {
    return res.status(400).json({ error: 'Enter a required-hours value greater than zero.' });
  }
  try {
    await setFullSemesterRequiredHours(hours);
    res.json({ fullSemesterRequiredHours: hours });
  } catch (err) {
    console.error('Error saving full-semester requirement:', err);
    res.status(500).json({ error: 'Unable to save full-semester requirement.' });
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
  const RANGE = `${ATTENDANCE_RESPONSE_SHEET}!A2:C1000`;

  try {
    const masterData = await getBuildAttendanceMaster();

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

    let totalMeetingHours = await getTotalMeetingHours();
    totalMeetingHours += officialMeetingHours;
    await setTotalMeetingHours(totalMeetingHours);

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

    const fullRoster = await getMembers();
    fullRoster.forEach(email => {
      const hasLogged = masterData[email]?.some(m => m.date === currentSessionDate);
      if (!hasLogged) {
        if (!masterData[email]) masterData[email] = [];
        masterData[email].push({
          date: currentSessionDate,
          durationHours: 0
        });
      }
    });
    
    await saveBuildAttendanceMaster(masterData);


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
    const masterData = await getBuildAttendanceMaster();
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

function calendarMeetingFromRequest(body) {
  const date = normalizeMeetingDate(body?.date);
  const totalHours = Number(body?.totalHours);
  if (!date || !Number.isFinite(totalHours) || totalHours < 0) return null;
  return {
    title: String(body?.title || 'Meeting').trim() || 'Meeting',
    date,
    startTime: String(body?.startTime || '').trim(),
    endTime: String(body?.endTime || '').trim(),
    totalHours,
    notes: String(body?.notes || '').trim(),
    published: body?.published === true,
  };
}

// Published meeting plans are visible to every member and power the personal
// attendance calculator. They are separate from official attendance records.
app.get('/attendance/calendar', async (req, res) => {
  try {
    res.json({ meetings: await getCalendarMeetings({ publishedOnly: true }) });
  } catch (err) {
    console.error('Error loading published calendar:', err);
    res.status(500).json({ error: 'Unable to load meeting calendar.' });
  }
});

app.get('/attendance/calendar/manage', async (req, res) => {
  try {
    res.json({ meetings: await getCalendarMeetings() });
  } catch (err) {
    console.error('Error loading managed calendar:', err);
    res.status(500).json({ error: 'Unable to load meeting calendar.' });
  }
});

app.post('/attendance/calendar', async (req, res) => {
  const meeting = calendarMeetingFromRequest(req.body);
  if (!meeting) return res.status(400).json({ error: 'Enter a valid date and non-negative total hours.' });
  try {
    const document = attendanceCalendarCollection().doc();
    const createdAt = new Date().toISOString();
    await document.set({ ...meeting, createdAt });
    res.status(201).json({ meeting: { id: document.id, ...meeting, createdAt } });
  } catch (err) {
    console.error('Error adding calendar meeting:', err);
    res.status(500).json({ error: 'Unable to add meeting.' });
  }
});

app.put('/attendance/calendar/:id', async (req, res) => {
  const meeting = calendarMeetingFromRequest(req.body);
  if (!meeting) return res.status(400).json({ error: 'Enter a valid date and non-negative total hours.' });
  try {
    const document = attendanceCalendarCollection().doc(req.params.id);
    if (!(await document.get()).exists) return res.status(404).json({ error: 'Meeting not found.' });
    await document.set(meeting, { merge: true });
    res.json({ meeting: { id: document.id, ...meeting } });
  } catch (err) {
    console.error('Error updating calendar meeting:', err);
    res.status(500).json({ error: 'Unable to update meeting.' });
  }
});

app.delete('/attendance/calendar/:id', async (req, res) => {
  try {
    const document = attendanceCalendarCollection().doc(req.params.id);
    if (!(await document.get()).exists) return res.status(404).json({ error: 'Meeting not found.' });
    await document.delete();
    res.json({ deleted: req.params.id });
  } catch (err) {
    console.error('Error deleting calendar meeting:', err);
    res.status(500).json({ error: 'Unable to delete meeting.' });
  }
});



// get attendance for a single user by email using preseason_master + different hours
app.get('/attendance/preseason/:email', async (req, res) => {
  const email = req.params.email?.toLowerCase();
  if (!email) return res.status(400).json({ error: 'Email required' });

  try {
    const masterData = await getPreseasonAttendanceMaster();
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

// Saved seasons are read-only snapshots. The legacy preseason source remains
// available as the first selectable history season while it is being used.
app.get('/attendance/seasons', async (req, res) => {
  try {
    await ensureLegacyPreseasonHistory();
    const seasons = await getArchivedAttendanceSeasons();
    res.json({ seasons: seasons.map(({ id, name, type, archivedAt }) => ({ id, name, type, archivedAt })) });
  } catch (err) {
    console.error('Error loading attendance seasons:', err);
    res.status(500).json({ error: 'Unable to load attendance seasons.' });
  }
});

app.get('/attendance/seasons/:id/:email', async (req, res) => {
  const email = req.params.email?.toLowerCase();
  if (!email) return res.status(400).json({ error: 'Email required' });
  try {
    let season;
    let records;
    const archivedSeason = await getArchivedAttendanceSeason(req.params.id);
    if (!archivedSeason) return res.status(404).json({ error: 'Saved season not found.' });
    records = archivedSeason.records[email] || [];
    season = archivedSeason;

    const isRookie = records.some(entry => entry?.rookie === true);
    const meetings = records
      .filter(entry => entry?.date && (typeof entry.durationHours === 'number' || entry.error === true))
      .sort((a, b) => new Date(a.date) - new Date(b.date));
    const totalHoursAttended = meetings.reduce(
      (sum, entry) => sum + (typeof entry.durationHours === 'number' ? entry.durationHours : 0),
      0
    );
    const totalMeetingHours = season.type === 'preseason'
      ? 83.5 - (isRookie ? 3.5 : 0)
      : Number(season.totalMeetingHours) || 0;
    const attendancePercentage = totalMeetingHours > 0
      ? parseFloat(((totalHoursAttended / totalMeetingHours) * 100).toFixed(2))
      : 0;

    res.json({
      season: { id: req.params.id, name: season.name, type: season.type },
      email,
      meetings,
      totalHoursAttended,
      totalMeetingHours,
      attendancePercentage,
    });
  } catch (err) {
    console.error('Error loading saved season attendance:', err);
    res.status(500).json({ error: 'Unable to load saved season attendance.' });
  }
});

app.post('/attendance/seasons/archive', async (req, res) => {
  try {
    const season = await archiveAndResetBuildAttendance(req.body?.name);
    res.status(201).json({ season });
  } catch (err) {
    const message = err instanceof Error ? err.message : 'Unable to archive current season.';
    const status = message === 'A season name is required.' || message === 'A saved season already has that name.'
      ? 400
      : 500;
    if (status === 500) console.error('Error archiving attendance season:', err);
    res.status(status).json({ error: message });
  }
});


// get attendance for a single user by email using attendance_master
app.get('/attendance/:email', async (req, res) => {
  const email = req.params.email?.toLowerCase();
  if (!email) return res.status(400).json({ error: 'Email required' });

  try {
    const masterData = await getBuildAttendanceMaster();
    let userData = masterData[email] || [];

    const meetings = userData
      .filter(m => m.date && (typeof m.durationHours === 'number' || m.error === true))
      .sort((a, b) => {
        const aDate = new Date(a.date);
        const bDate = new Date(b.date);
        return aDate - bDate; 
      });   
      
    let totalMeetingHours = await getTotalMeetingHours();
    const fullSemesterRequiredHours = await getFullSemesterRequiredHours();

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
      fullSemesterRequiredHours,
      attendancePercentage
    });

  } catch (err) {
    console.error('Error fetching attendance percentage:', err);
    res.status(500).json({ error: 'Unable to fetch attendance data.' });
  }
});

app.get('/attendance/master/download', async (req, res) => {
  try {
    const master = await getBuildAttendanceMaster();
    res.attachment('attendance_master.json').send(JSON.stringify(master, null, 2));
  } catch (err) {
    console.error('Error downloading master attendance:', err);
    res.status(500).send('Error downloading master attendance');
  }
});

app.get('/attendance/total/download', async (req, res) => {
  try {
    const totalHours = await getTotalMeetingHours();
    res.attachment('total_meeting_hours.json').send(JSON.stringify({ totalHours }, null, 2));
  } catch (err) {
    console.error('Error downloading total meeting hours:', err);
    res.status(500).send('Error downloading total meeting hours');
  }
});

// resolves flagged emails after attendance update
app.post("/attendance/resolve", async (req, res) => {
  const { email, date, durationHours, reason, keepFlagged } = req.body;

  if (!email || !date) {
    return res.status(400).json({ message: "Missing email or date" });
  }

  function normalizeDate(d) {
    if (!d) return "";
    return d.split(" ")[0];
  }

  try {
    const master = await getBuildAttendanceMaster();

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

    await saveBuildAttendanceMember(email, master[email]);
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

    const masterData = await getBuildAttendanceMaster();

    if (!masterData[normalizedEmail]) {
      return res.status(404).json({
        error: "No attendance records found for this email"
      });
    }

    masterData[normalizedEmail] = masterData[normalizedEmail].filter(
      (entry) => entry.date !== date
    );

    masterData[normalizedEmail].push(payload);

    await saveBuildAttendanceMember(normalizedEmail, masterData[normalizedEmail]);


    return res.json({ success: true });
  } catch (err) {
    console.error("Manual update error:", err);
    return res.status(500).json({ error: "Internal server error" });
  }
});

// Submits a member's request to correct a single day's attendance.
app.post('/attendance/adjustments', async (req, res) => {
  const { email, date, arrivalTime, departureTime, hoursHere } = req.body;
  const durationHours = Number(hoursHere);

  if (!email || !date || !arrivalTime || !departureTime || !Number.isFinite(durationHours)) {
    return res.status(400).json({ error: 'Email, date, arrival time, departure time, and hours are required.' });
  }
  if (durationHours < 0 || durationHours > 24) {
    return res.status(400).json({ error: 'Hours must be between 0 and 24.' });
  }

  try {
    const settings = await getAttendanceAdjustmentSettings();
    if (settings.closedDates.includes(normalizeMeetingDate(date))) {
      return res.status(403).json({ error: `Adjustments are closed for ${date}.` });
    }
    const masterData = await getBuildAttendanceMaster();
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
    await saveAttendanceAdjustment(adjustment);
    res.status(201).json({ adjustment });
  } catch (err) {
    console.error('Error saving attendance adjustment:', err);
    res.status(500).json({ error: 'Unable to save attendance adjustment.' });
  }
});

// Resolves an adjustment. Approving it updates the attendance record for that date.
app.post('/attendance/adjustments/:id/resolve', async (req, res) => {
  const { status } = req.body;
  if (status !== 'approved' && status !== 'rejected') {
    return res.status(400).json({ error: 'Status must be approved or rejected.' });
  }

  try {
    const adjustment = (await getAttendanceAdjustments()).find(item => item.id === req.params.id);
    if (!adjustment) return res.status(404).json({ error: 'Adjustment request not found.' });
    if (adjustment.status !== 'pending') {
      return res.status(400).json({ error: 'This request has already been resolved.' });
    }

    if (status === 'approved') {
      const masterData = await getBuildAttendanceMaster();
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

      await saveBuildAttendanceMember(email, masterData[email]);
    }

    adjustment.status = status;
    adjustment.resolvedAt = new Date().toISOString();
    await saveAttendanceAdjustment(adjustment);
    res.json({ adjustment });
  } catch (err) {
    console.error('Error resolving attendance adjustment:', err);
    res.status(500).json({ error: 'Unable to resolve attendance adjustment.' });
  }
});

// get attendance for the full team for both preseason and build season
app.get("/attendance/team/full", async (req, res) => {
  try {
    const isPreseason = req.query.isPreseason === "true";
    const master = isPreseason
      ? await getPreseasonAttendanceMaster()
      : await getBuildAttendanceMaster();

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
    } else totalMeetingHours = await getTotalMeetingHours();

    const activeMembers = isPreseason ? Object.keys(master) : await getMembers();
    const team = activeMembers.map(email => {
      const records = master[email] || [];
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

app.get('/total-hours', async (req, res) => {
  try {
    const attendanceData = await getBuildAttendanceMaster();

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


app.get("/attendance/team/hours", async (req, res) => {
  try {
    const masterData = await getBuildAttendanceMaster();

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
app.listen(PORT, () => {
  console.log(`Backend running on port ${PORT}`);
});
