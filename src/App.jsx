import { BrowserRouter, Routes, Route, Navigate } from 'react-router-dom';
import { AuthProvider, useAuth } from './contexts/AuthContext';
import { ToastProvider } from './components/Toast';
import ProtectedRoute from './components/ProtectedRoute';
import AppLayout from './components/layout/AppLayout';
import PublicLayout from './components/layout/PublicLayout';
import LoginPage from './pages/LoginPage';
import UnauthorizedPage from './pages/UnauthorizedPage';

// Admin Pages
import AdminOverview from './pages/admin/Overview';
import TeamsManager from './pages/admin/TeamsManager';
import MatchesManager from './pages/admin/MatchesManager';
import FixturesManager from './pages/admin/FixturesManager';
import AdminLeaderboards from './pages/admin/Leaderboards';
import AuditLogs from './pages/admin/AuditLogs';
import ExportData from './pages/admin/ExportData';
import UsersManager from './pages/admin/UsersManager';

// Leader Pages
import LeaderDashboard from './pages/leader/Dashboard';
import SharedTeams from './pages/shared/SharedTeams';
import LeaderPlayers from './pages/leader/Players';
import LeaderFixtures from './pages/leader/Fixtures';
import LeaderResults from './pages/leader/Results';
import LeaderLeaderboard from './pages/leader/Leaderboard';

// Player Pages
import PlayerDashboard from './pages/player/Dashboard';

// Public Viewer Pages (NO LOGIN NEEDED)
import ViewerTeams from './pages/viewer/Teams';
import ViewerFixtures from './pages/viewer/Fixtures';
import ViewerResults from './pages/viewer/Results';
import ViewerLeaderboards from './pages/viewer/Leaderboards';

function RoleRedirect() {
  const { user, profile, loading } = useAuth();

  if (loading) {
    return (
      <div className="loading-screen">
        <div className="loader"></div>
        <p>LOADING...</p>
      </div>
    );
  }

  // If not logged in at all, go to public viewer
  if (!user) return <Navigate to="/live" replace />;

  // User is logged in, but profile fetch failed (RLS, missing row, etc)
  // Send them to login so they see the error message instead of being dumped in /live
  if (!profile) return <Navigate to="/login" replace />;

  switch (profile.role) {
    case 'admin':
      return <Navigate to="/admin" replace />;
    case 'game_leader':
      return <Navigate to="/leader" replace />;
    case 'player':
      return <Navigate to="/player" replace />;
    default:
      return <Navigate to="/live" replace />;
  }
}

export default function App() {
  return (
    <BrowserRouter>
      <AuthProvider>
        <ToastProvider>
          <Routes>
            {/* Public login */}
            <Route path="/login" element={<LoginPage />} />
            <Route path="/unauthorized" element={<UnauthorizedPage />} />

            {/* Role-based redirect */}
            <Route path="/" element={<Navigate to="/live" replace />} />

            {/* ============================================ */}
            {/* PUBLIC VIEWER — NO LOGIN REQUIRED            */}
            {/* Anyone can see fixtures, results, standings  */}
            {/* ============================================ */}
            <Route path="/live" element={<PublicLayout />}>
              <Route index element={<ViewerTeams />} />
              <Route path="fixtures" element={<ViewerFixtures />} />
              <Route path="results" element={<ViewerResults />} />
              <Route path="leaderboards" element={<ViewerLeaderboards />} />
            </Route>

            {/* ============================================ */}
            {/* ADMIN — requires admin role                  */}
            {/* ============================================ */}
            <Route
              path="/admin"
              element={
                <ProtectedRoute allowedRoles={['admin']}>
                  <AppLayout />
                </ProtectedRoute>
              }
            >
              <Route index element={<AdminOverview />} />
              <Route path="teams" element={<TeamsManager />} />
              <Route path="fixtures" element={<FixturesManager />} />
              <Route path="matches" element={<MatchesManager />} />
              <Route path="leaderboards" element={<AdminLeaderboards />} />
              <Route path="users" element={<UsersManager />} />
              <Route path="audit" element={<AuditLogs />} />
              <Route path="export" element={<ExportData />} />
            </Route>

            {/* ============================================ */}
            {/* GAME LEADER — requires game_leader role      */}
            {/* ============================================ */}
            <Route
              path="/leader"
              element={
                <ProtectedRoute allowedRoles={['game_leader']}>
                  <AppLayout />
                </ProtectedRoute>
              }
            >
              <Route index element={<LeaderDashboard />} />
              <Route path="teams" element={<SharedTeams />} />
              <Route path="players" element={<LeaderPlayers />} />
              <Route path="fixtures" element={<LeaderFixtures />} />
              <Route path="results" element={<LeaderResults />} />
              <Route path="leaderboard" element={<LeaderLeaderboard />} />
            </Route>

            {/* ============================================ */}
            {/* PLAYER — requires player role                */}
            {/* ============================================ */}
            <Route
              path="/player"
              element={
                <ProtectedRoute allowedRoles={['player']}>
                  <AppLayout />
                </ProtectedRoute>
              }
            >
              <Route index element={<PlayerDashboard />} />
              <Route path="teams" element={<SharedTeams />} />
            </Route>

            {/* Catch-all → public view */}
            <Route path="*" element={<Navigate to="/live" replace />} />
          </Routes>
        </ToastProvider>
      </AuthProvider>
    </BrowserRouter>
  );
}
