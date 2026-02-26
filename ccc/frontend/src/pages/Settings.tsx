import { useState, useEffect } from "react";
import { useAuth } from "../contexts/AuthContext";
import { useToast } from "../contexts/ToastContext";
import { Pencil, Circle, X, ChevronDown } from "lucide-react";
import ConfirmModal from "../components/ConfirmModal";
import {
  fetchMyConfig,
  updateMyConfig,
  fetchGlobalSettings,
  updateGlobalSettings,
  fetchUsers,
  createUser,
  updateUser,
  deactivateUser,
  activateUser,
  resetUserPassword,
  promoteToAdmin,
  demoteFromAdmin,
  changeMyPassword,
  fetchSzuruCategories,
  fetchCategoryMappings,
  updateCategoryMappings,
  fetchSupportedSites,
  UserResponse,
  UserConfig,
  GlobalSettings,
} from "../api";

type Tab = "profile" | "site-creds" | "global" | "users";

export default function Settings() {
  const { isAdmin } = useAuth();
  const [activeTab, setActiveTab] = useState<Tab>("profile");

  return (
    <div className="settings-page">
      <h2>Settings</h2>

      <div className="tabs">
        <button
          onClick={() => setActiveTab("profile")}
          className={`tab-button ${activeTab === "profile" ? "active" : ""}`}
        >
          My Profile
        </button>
        <button
          onClick={() => setActiveTab("site-creds")}
          className={`tab-button ${activeTab === "site-creds" ? "active" : ""}`}
        >
          Site Credentials
        </button>
        {isAdmin && (
          <>
            <button
              onClick={() => setActiveTab("global")}
              className={`tab-button ${activeTab === "global" ? "active" : ""}`}
            >
              Global Settings
            </button>
            <button
              onClick={() => setActiveTab("users")}
              className={`tab-button ${activeTab === "users" ? "active" : ""}`}
            >
              Users
            </button>
          </>
        )}
      </div>

      <div className="tab-content">
        {activeTab === "profile" && <ProfileTab />}
        {activeTab === "site-creds" && <SiteCredentialsTab />}
        {activeTab === "global" && isAdmin && <GlobalSettingsTab />}
        {activeTab === "users" && isAdmin && <UsersTab />}
      </div>
    </div>
  );
}

// ============================================================================
// Profile Tab
// ============================================================================

function ProfileTab() {
  const { isAdmin } = useAuth();
  const { showToast } = useToast();
  const [config, setConfig] = useState<UserConfig | null>(null);
  const [form, setForm] = useState({ szuru_url: "", szuru_public_url: "", szuru_username: "", szuru_token: "" });
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [categories, setCategories] = useState<Array<{ name: string; color: string; order: number }> | null>(null);
  const [fetchingCategories, setFetchingCategories] = useState(false);
  const [categoryMappings, setCategoryMappings] = useState<Record<string, string>>({});
  const [savingMappings, setSavingMappings] = useState(false);

  useEffect(() => {
    Promise.all([
      fetchMyConfig(),
      fetchCategoryMappings()
    ])
      .then(([c, mappings]) => {
        setConfig(c);
        setForm({
          szuru_url: c.szuru_url || "",
          szuru_public_url: c.szuru_public_url || "",
          szuru_username: c.szuru_username || "",
          szuru_token: "",
        });
        setCategoryMappings(mappings.mappings || {});
      })
      .catch((err) => showToast("Failed to load config: " + err.message, "error"))
      .finally(() => setLoading(false));
  }, [showToast]);

  async function handleSave() {
    setSaving(true);
    try {
      await updateMyConfig({
        szuru_url: form.szuru_url || undefined,
        szuru_public_url: form.szuru_public_url || undefined,
        szuru_username: form.szuru_username || undefined,
        szuru_token: form.szuru_token || undefined,
      });
      // Reload config to get the saved token
      const updatedConfig = await fetchMyConfig();
      setConfig(updatedConfig);
      showToast("Profile updated!", "success");
      setForm({ ...form, szuru_token: "" });
    } catch (err: any) {
      showToast("Failed to update: " + err.message, "error");
    } finally {
      setSaving(false);
    }
  }

  async function handleTestConnection() {
    if (!form.szuru_url || !form.szuru_username) {
      showToast("Please enter Szurubooru URL and username first", "error");
      return;
    }

    // Always test with current form values, not saved config
    const token = form.szuru_token || config?.szuru_token || "";
    if (!token) {
      showToast("Please enter or save your token first", "error");
      return;
    }

    setFetchingCategories(true);
    try {
      const result = await fetchSzuruCategories(form.szuru_url, form.szuru_username, token);
      if (result.error) {
        showToast("Connection failed: " + result.error, "error");
      } else if (result.results) {
        showToast("Connection successful! Found " + result.results.length + " categories.", "success");
      }
    } catch (err: any) {
      showToast("Connection failed: " + err.message, "error");
    } finally {
      setFetchingCategories(false);
    }
  }

  async function handleFetchCategories() {
    if (!form.szuru_url || !form.szuru_username) {
      showToast("Please enter Szurubooru URL and username first", "error");
      return;
    }

    // Use stored token if available, otherwise use form token
    const token = config?.szuru_token || form.szuru_token || "";
    if (!token) {
      showToast("Please save your token first or enter it in the form", "error");
      return;
    }

    setFetchingCategories(true);
    try {
      const result = await fetchSzuruCategories(form.szuru_url, form.szuru_username, token);
      if (result.error) {
        showToast("Failed to fetch categories: " + result.error, "error");
        setCategories(null);
      } else if (result.results) {
        setCategories(result.results.sort((a, b) => a.order - b.order));
        showToast("Categories fetched successfully! You can now map them below.", "success");
      }
    } catch (err: any) {
      showToast("Failed to fetch categories: " + err.message, "error");
      setCategories(null);
    } finally {
      setFetchingCategories(false);
    }
  }

  async function handleSaveMappings() {
    if (!isAdmin) return;
    setSavingMappings(true);
    try {
      await updateCategoryMappings(categoryMappings);
      showToast("Category mappings saved!", "success");
    } catch (err: any) {
      showToast("Failed to save mappings: " + err.message, "error");
    } finally {
      setSavingMappings(false);
    }
  }

  if (loading) return <div className="card"><p>Loading...</p></div>;

  return (
    <div className="card">
      <h3>Szurubooru Configuration</h3>
      <div className="settings-form">
        <div className="form-group">
          <label>Szurubooru URL (Internal/API)</label>
          <input
            type="text"
            value={form.szuru_url}
            onChange={(e) => setForm({ ...form, szuru_url: e.target.value })}
            placeholder="http://192.168.1.100:8080"
          />
          <small style={{ fontSize: "0.75rem", color: "var(--text-muted)" }}>
            Internal URL used for API calls (can be local IP)
          </small>
        </div>
        <div className="form-group">
          <label>Szurubooru Public URL (Optional)</label>
          <input
            type="text"
            value={form.szuru_public_url}
            onChange={(e) => setForm({ ...form, szuru_public_url: e.target.value })}
            placeholder="https://booru.example.com"
          />
          <small style={{ fontSize: "0.75rem", color: "var(--text-muted)" }}>
            Public URL for sharing links (e.g., in mobile app). Leave empty to use internal URL.
          </small>
        </div>
        <div className="form-group">
          <label>Szurubooru Username</label>
          <input
            type="text"
            value={form.szuru_username}
            onChange={(e) => setForm({ ...form, szuru_username: e.target.value })}
          />
        </div>
        <div className="form-group">
          <label>Szurubooru API Token</label>
          <input
            type="password"
            value={form.szuru_token}
            onChange={(e) => setForm({ ...form, szuru_token: e.target.value })}
            placeholder="Leave blank to keep existing"
          />
        </div>
        <div className="form-actions">
          <button type="submit" onClick={handleSave} disabled={saving} className="btn btn-primary">
            {saving ? "Saving..." : "Save Profile"}
          </button>
          <button type="button" onClick={handleTestConnection} disabled={fetchingCategories}>
            {fetchingCategories ? "Testing..." : "Test Connection"}
          </button>
          <button type="button" onClick={handleFetchCategories} disabled={fetchingCategories}>
            {fetchingCategories ? "Fetching..." : "Fetch Tag Categories"}
          </button>
        </div>

        {categories && categories.length > 0 && (
          <div className="card" style={{ marginTop: "1rem", background: "var(--bg)" }}>
            <h4 style={{ fontSize: "0.9rem", marginBottom: "0.75rem", color: "var(--text-muted)" }}>
              Tag Categories from Szurubooru
            </h4>
            <div className="tag-list">
              {categories.map((cat) => (
                <span
                  key={cat.name}
                  className="tag"
                  style={{
                    background: cat.color || "var(--bg-card)",
                    color: "white",
                    border: `1px solid ${cat.color || "var(--border)"}`,
                  }}
                >
                  {cat.name}
                </span>
              ))}
            </div>
            <p style={{ marginTop: "0.75rem", fontSize: "0.75rem", color: "var(--text-muted)", opacity: 0.8 }}>
              These categories are automatically fetched from your Szurubooru instance.
            </p>
          </div>
        )}

        {/* Category Mappings */}
        <div className="card" style={{ marginTop: "1rem", background: "var(--bg)" }}>
          <h4 style={{ fontSize: "0.9rem", marginBottom: "0.75rem", color: "var(--text-muted)" }}>
            Category Mappings
          </h4>
          <p style={{ fontSize: "0.75rem", color: "var(--text-muted)", marginBottom: "1rem" }}>
            Map internal category types to your Szurubooru instance's categories. These mappings are specific to your account.
          </p>
          <div className="settings-form">
            {["general", "artist", "character", "copyright", "meta"].map((internalCat) => (
              <div key={internalCat} className="form-group">
                <label style={{ textTransform: "capitalize" }}>{internalCat}</label>
                {categories && categories.length > 0 ? (
                  <select
                    value={categoryMappings[internalCat] || ""}
                    onChange={(e) => setCategoryMappings({ ...categoryMappings, [internalCat]: e.target.value })}
                  >
                    <option value="">-- Select Category --</option>
                    {categories.map((cat) => (
                      <option key={cat.name} value={cat.name}>
                        {cat.name}
                      </option>
                    ))}
                  </select>
                ) : (
                  <input
                    type="text"
                    value={categoryMappings[internalCat] || ""}
                    onChange={(e) => setCategoryMappings({ ...categoryMappings, [internalCat]: e.target.value })}
                    placeholder={`e.g., ${internalCat}`}
                  />
                )}
              </div>
            ))}
            <div className="form-actions">
              <button
                type="button"
                onClick={handleSaveMappings}
                disabled={savingMappings}
                className="btn btn-primary"
              >
                {savingMappings ? "Saving..." : "Save Mappings"}
              </button>
            </div>
          </div>
        </div>

        {/* Change Password */}
        <div className="card" style={{ marginTop: "1rem", background: "var(--bg)" }}>
          <h4 style={{ fontSize: "0.9rem", marginBottom: "0.75rem", color: "var(--text-muted)" }}>
            Change Password
          </h4>
          <ChangePasswordSection />
        </div>
      </div>
    </div>
  );
}

// ============================================================================
// Change Password Section
// ============================================================================

function ChangePasswordSection() {
  const { showToast } = useToast();
  const [form, setForm] = useState({ oldPassword: "", newPassword: "", confirmPassword: "" });
  const [saving, setSaving] = useState(false);

  async function handleChangePassword() {
    // Validation
    if (!form.oldPassword || !form.newPassword || !form.confirmPassword) {
      showToast("All fields are required", "error");
      return;
    }

    if (form.newPassword.length < 4) {
      showToast("New password must be at least 4 characters", "error");
      return;
    }

    if (form.newPassword !== form.confirmPassword) {
      showToast("New passwords do not match", "error");
      return;
    }

    setSaving(true);
    try {
      await changeMyPassword(form.oldPassword, form.newPassword);
      showToast("Password changed successfully!", "success");
      setForm({ oldPassword: "", newPassword: "", confirmPassword: "" });
    } catch (err: any) {
      showToast(err.message || "Failed to change password", "error");
    } finally {
      setSaving(false);
    }
  }

  return (
    <div className="settings-form">
      <div className="form-group">
        <label>Current Password</label>
        <input
          type="password"
          value={form.oldPassword}
          onChange={(e) => setForm({ ...form, oldPassword: e.target.value })}
          placeholder="Enter current password"
        />
      </div>
      <div className="form-group">
        <label>New Password</label>
        <input
          type="password"
          value={form.newPassword}
          onChange={(e) => setForm({ ...form, newPassword: e.target.value })}
          placeholder="Enter new password"
        />
      </div>
      <div className="form-group">
        <label>Confirm New Password</label>
        <input
          type="password"
          value={form.confirmPassword}
          onChange={(e) => setForm({ ...form, confirmPassword: e.target.value })}
          placeholder="Confirm new password"
        />
      </div>
      <div className="form-actions">
        <button
          type="button"
          onClick={handleChangePassword}
          disabled={saving}
          className="btn btn-primary"
        >
          {saving ? "Changing..." : "Change Password"}
        </button>
      </div>
    </div>
  );
}

// ============================================================================
// Site Credentials Tab
// ============================================================================

function SiteCredentialsTab() {
  const { showToast } = useToast();
  const [config, setConfig] = useState<UserConfig | null>(null);
  const [creds, setCreds] = useState<Record<string, Record<string, string>>>({});
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [expandedSite, setExpandedSite] = useState<string | null>(null);
  const [sites, setSites] = useState<Array<{ name: string; fields: string[] }>>([]);

  useEffect(() => {
    fetchSupportedSites()
      .then(setSites)
      .catch(() => {
        showToast("Failed to load supported sites", "error");
      });
  }, [showToast]);

  useEffect(() => {
    fetchMyConfig()
      .then((c) => {
        setConfig(c);
        setCreds(c.site_credentials || {});
      })
      .catch((err) => showToast("Failed to load config: " + err.message, "error"))
      .finally(() => setLoading(false));
  }, [showToast]);

  async function handleSave() {
    setSaving(true);
    try {
      await updateMyConfig({ site_credentials: creds });
      showToast("Site credentials updated!", "success");
    } catch (err: any) {
      showToast("Failed to update: " + err.message, "error");
    } finally {
      setSaving(false);
    }
  }

  function updateCred(site: string, key: string, value: string) {
    setCreds({
      ...creds,
      [site]: { ...(creds[site] || {}), [key]: value },
    });
  }

  if (loading) return <div className="card"><p>Loading...</p></div>;

  return (
    <div className="card">
      <h3>Site Credentials</h3>
      <p style={{ fontSize: "0.85rem", color: "var(--text-muted)", marginBottom: "1rem" }}>
        Configure authentication for gallery-dl supported sites. All credentials are encrypted in the database.
      </p>

      {sites.map((site) => (
        <div key={site.name} className="accordion">
          <button
            className="accordion-header"
            onClick={() => setExpandedSite(expandedSite === site.name ? null : site.name)}
          >
            <span style={{ textTransform: "capitalize", fontWeight: 500 }}>{site.name}</span>
            <ChevronDown size={16} className={`accordion-icon ${expandedSite === site.name ? "open" : ""}`} />
          </button>
          {expandedSite === site.name && (
            <div className="accordion-content">
              {site.name === "reddit" && (
                <p style={{ fontSize: "0.8rem", color: "var(--text-muted)", marginBottom: "0.75rem" }}>
                  Reddit has ended self-service API access. Request API access manually via{" "}
                  <a href="https://support.reddithelp.com/hc/en-us/requests/new?ticket_form_id=14868593862164&tf_14867328473236=api_request_type_enterprise" target="_blank" rel="noopener noreferrer">Reddit support</a>.
                  Use the client ID, secret, and username they provide in the fields below.
                </p>
              )}
              <div className="settings-form">
                {site.fields.map((field) => (
                  <div key={field} className="form-group">
                    <label style={{ textTransform: "capitalize" }}>
                      {field.replace(/_/g, " ").replace(/-/g, " ")}
                    </label>
                    {field === "cookies" ? (
                      <textarea
                        value={creds[site.name]?.[field] || ""}
                        onChange={(e) => updateCred(site.name, field, e.target.value)}
                        placeholder="Netscape cookie format"
                        rows={3}
                        style={{ fontFamily: "Monaco, Courier New, monospace", fontSize: "0.8rem" }}
                      />
                    ) : (
                      <input
                        type={field.includes("password") || field.includes("secret") || field.includes("token") ? "password" : "text"}
                        value={creds[site.name]?.[field] || ""}
                        onChange={(e) => updateCred(site.name, field, e.target.value)}
                        placeholder={field === "access-token" ? "From instance Settings → API" : undefined}
                      />
                    )}
                  </div>
                ))}
              </div>
            </div>
          )}
        </div>
      ))}

      <div className="form-actions" style={{ marginTop: "1rem" }}>
        <button type="submit" onClick={handleSave} disabled={saving} className="btn btn-primary">
          {saving ? "Saving..." : "Save Credentials"}
        </button>
      </div>
    </div>
  );
}

// ============================================================================
// Global Settings Tab (Admin Only)
// ============================================================================

function GlobalSettingsTab() {
  const { showToast } = useToast();
  const [settings, setSettings] = useState<GlobalSettings | null>(null);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    fetchGlobalSettings()
      .then((s) => setSettings(s))
      .catch((err) => showToast("Failed to load: " + err.message, "error"))
      .finally(() => setLoading(false));
  }, [showToast]);

  async function handleSave() {
    if (!settings) return;
    setSaving(true);
    try {
      await updateGlobalSettings(settings);
      showToast("Global settings updated!", "success");
    } catch (err: any) {
      showToast("Failed to update: " + err.message, "error");
    } finally {
      setSaving(false);
    }
  }

  if (loading) return <div className="card"><p>Loading...</p></div>;
  if (!settings) return <div className="card"><p>Failed to load settings</p></div>;

  return (
    <div className="card">
      <h3>Global Settings</h3>
      <p style={{ fontSize: "0.85rem", color: "var(--text-muted)", marginBottom: "1rem" }}>
        Configure system-wide settings. All changes take effect on the next job without a restart.
      </p>

      <div className="settings-form">
        <h4 style={{ fontSize: "1rem", marginBottom: "0.75rem", color: "var(--text)" }}>WD14 Tagger</h4>
        <div className="form-group">
          <div style={{ display: "flex", alignItems: "center", gap: "1rem" }}>
            <label style={{ marginBottom: 0 }}>Enable WD14 AI Tagging</label>
            <label className="toggle-switch">
              <input
                type="checkbox"
                checked={settings.wd14_enabled}
                onChange={(e) => setSettings({ ...settings, wd14_enabled: e.target.checked })}
              />
              <span className="toggle-slider"></span>
            </label>
          </div>
          <small>Automatically tag images using the WD14 model (requires ~2GB model download on first use)</small>
        </div>
        {settings.wd14_enabled && (
          <>
            <div className="form-group">
              <label>Confidence Threshold</label>
              <input
                type="number"
                step="0.01"
                min="0"
                max="1"
                value={settings.wd14_confidence_threshold}
                onChange={(e) => setSettings({ ...settings, wd14_confidence_threshold: parseFloat(e.target.value) })}
              />
              <small>Minimum confidence to include a tag (0.0 - 1.0, recommended: 0.35)</small>
            </div>
            <div className="form-group">
              <label>Max Tags</label>
              <input
                type="number"
                min="1"
                value={settings.wd14_max_tags}
                onChange={(e) => setSettings({ ...settings, wd14_max_tags: parseInt(e.target.value) })}
              />
              <small>Maximum number of AI tags per image</small>
            </div>
          </>
        )}

        <h4 style={{ fontSize: "1rem", marginTop: "1.5rem", marginBottom: "0.75rem", color: "var(--text)" }}>Video Tagging</h4>
        <div className="form-group">
          <div style={{ display: "flex", alignItems: "center", gap: "1rem" }}>
            <label style={{ marginBottom: 0 }}>Enable Video Frame Tagging</label>
            <label className="toggle-switch">
              <input
                type="checkbox"
                checked={settings.video_tagging_enabled}
                onChange={(e) => setSettings({ ...settings, video_tagging_enabled: e.target.checked })}
              />
              <span className="toggle-slider"></span>
            </label>
          </div>
          <small>Extract frames from videos using scene detection and tag them with WD14 (requires WD14 to be enabled)</small>
        </div>
        {settings.video_tagging_enabled && (
          <>
            <div className="form-group">
              <label>Scene Detection Threshold</label>
              <input
                type="number"
                step="0.05"
                min="0.05"
                max="1"
                value={settings.video_scene_threshold}
                onChange={(e) => setSettings({ ...settings, video_scene_threshold: parseFloat(e.target.value) })}
              />
              <small>FFmpeg scene change sensitivity (0.05 - 1.0, lower = more frames extracted, recommended: 0.3)</small>
            </div>
            <div className="form-group">
              <label>Max Frames</label>
              <input
                type="number"
                min="1"
                max="50"
                value={settings.video_max_frames}
                onChange={(e) => setSettings({ ...settings, video_max_frames: parseInt(e.target.value) })}
              />
              <small>Maximum number of frames to extract per video</small>
            </div>
            <div className="form-group">
              <label>Minimum Frame Ratio</label>
              <input
                type="number"
                step="0.05"
                min="0"
                max="1"
                value={settings.video_tag_min_frame_ratio}
                onChange={(e) => setSettings({ ...settings, video_tag_min_frame_ratio: parseFloat(e.target.value) })}
              />
              <small>A tag must appear in this fraction of frames to be kept (0.0 - 1.0, recommended: 0.3). Character tags are always kept.</small>
            </div>
            <div className="form-group">
              <label>Video Confidence Threshold</label>
              <input
                type="number"
                step="0.01"
                min="0"
                max="1"
                value={settings.video_confidence_threshold}
                onChange={(e) => setSettings({ ...settings, video_confidence_threshold: parseFloat(e.target.value) })}
              />
              <small>Minimum WD14 confidence for tags in video frames (0.0 - 1.0, default: 0.45). Higher than image threshold since individual frames are less reliable.</small>
            </div>
          </>
        )}

        <h4 style={{ fontSize: "1rem", marginTop: "1.5rem", marginBottom: "0.75rem", color: "var(--text)" }}>Worker Settings</h4>
        <div className="form-group">
          <label>Gallery-DL Timeout (seconds)</label>
          <input
            type="number"
            min="10"
            value={settings.gallery_dl_timeout}
            onChange={(e) => setSettings({ ...settings, gallery_dl_timeout: parseInt(e.target.value) })}
          />
          <small>Timeout for gallery-dl downloads</small>
        </div>
        <div className="form-group">
          <label>YT-DLP Timeout (seconds)</label>
          <input
            type="number"
            min="10"
            value={settings.ytdlp_timeout}
            onChange={(e) => setSettings({ ...settings, ytdlp_timeout: parseInt(e.target.value) })}
          />
          <small>Timeout for yt-dlp downloads</small>
        </div>
        <div className="form-group">
          <label>Max Retries</label>
          <input
            type="number"
            min="0"
            value={settings.max_retries}
            onChange={(e) => setSettings({ ...settings, max_retries: parseInt(e.target.value) })}
          />
          <small>Number of retry attempts for failed downloads</small>
        </div>
        <div className="form-group">
          <label>Retry Delay (seconds)</label>
          <input
            type="number"
            step="0.1"
            min="0"
            value={settings.retry_delay}
            onChange={(e) => setSettings({ ...settings, retry_delay: parseFloat(e.target.value) })}
          />
          <small>Delay between retry attempts</small>
        </div>

        <div className="form-actions">
          <button type="submit" onClick={handleSave} disabled={saving} className="btn btn-primary">
            {saving ? "Saving..." : "Save Global Settings"}
          </button>
        </div>
      </div>
    </div>
  );
}

// ============================================================================
// Users Tab (Admin Only)
// ============================================================================

function UsersTab() {
  const { user: currentUser } = useAuth();
  const { showToast } = useToast();
  const [users, setUsers] = useState<UserResponse[]>([]);
  const [loading, setLoading] = useState(true);
  const [showForm, setShowForm] = useState(false);
  const [form, setForm] = useState({ username: "", password: "", role: "user" });
  const [editingUser, setEditingUser] = useState<UserResponse | null>(null);

  useEffect(() => {
    loadUsers();
  }, []);

  async function loadUsers() {
    setLoading(true);
    try {
      const data = await fetchUsers();
      setUsers(data);
    } catch (err: any) {
      showToast("Failed to load users: " + err.message, "error");
    } finally {
      setLoading(false);
    }
  }

  async function handleCreate() {
    try {
      await createUser(form);
      showToast("User created!", "success");
      setShowForm(false);
      setForm({ username: "", password: "", role: "user" });
      loadUsers();
    } catch (err: any) {
      showToast("Failed to create user: " + err.message, "error");
    }
  }

  if (loading) return <div className="card"><p>Loading...</p></div>;

  return (
    <div className="card">
      <h3>User Management</h3>
      <p style={{ fontSize: "0.85rem", color: "var(--text-muted)", marginBottom: "1rem" }}>
        Create and manage user accounts. Each user can configure their own Szurubooru and site credentials.
      </p>

      <button onClick={() => setShowForm(!showForm)} className="btn btn-primary" style={{ marginBottom: "1rem" }}>
        {showForm ? "Cancel" : "+ Create User"}
      </button>

      {showForm && (
        <div className="card" style={{ marginBottom: "1.5rem", background: "var(--bg)" }}>
          <div className="settings-form">
            <div className="form-group">
              <label>Username</label>
              <input
                type="text"
                value={form.username}
                onChange={(e) => setForm({ ...form, username: e.target.value })}
                placeholder="Enter username"
              />
            </div>
            <div className="form-group">
              <label>Password</label>
              <input
                type="password"
                value={form.password}
                onChange={(e) => setForm({ ...form, password: e.target.value })}
                placeholder="Enter password"
              />
            </div>
            <div className="form-group">
              <label>Role</label>
              <select value={form.role} onChange={(e) => setForm({ ...form, role: e.target.value })}>
                <option value="user">User</option>
                <option value="admin">Admin</option>
              </select>
            </div>
            <div className="form-actions">
              <button type="submit" onClick={handleCreate} className="btn btn-primary">Create User</button>
              <button type="button" onClick={() => setShowForm(false)}>Cancel</button>
            </div>
          </div>
        </div>
      )}

      <table className="users-table">
        <thead>
          <tr>
            <th>Username</th>
            <th>Role</th>
            <th>Status</th>
            <th>Actions</th>
          </tr>
        </thead>
        <tbody>
          {users.map((u) => (
            <tr key={u.id}>
              <td>{u.username}</td>
              <td>
                <span className="badge" style={{
                  background: u.role === "admin" ? "rgba(196, 30, 58, 0.15)" : "rgba(255, 255, 255, 0.08)",
                  color: u.role === "admin" ? "var(--accent)" : "var(--text-muted)",
                  textTransform: "uppercase"
                }}>
                  {u.role}
                </span>
              </td>
              <td>
                {u.is_active ? (
                  <Circle size={12} fill="var(--green)" color="var(--green)" />
                ) : (
                  <Circle size={12} color="var(--text-muted)" />
                )}
              </td>
              <td>
                {currentUser?.username !== u.username ? (
                  <button
                    onClick={() => setEditingUser(u)}
                    title="Edit User"
                    className="btn btn-sm"
                    style={{
                      background: "rgba(196, 30, 58, 0.12)",
                      color: "var(--accent)",
                      border: "1px solid rgba(196, 30, 58, 0.35)",
                      padding: "0.35rem 0.5rem",
                      fontSize: "0.85rem",
                      display: "flex",
                      alignItems: "center",
                      justifyContent: "center",
                    }}
                  >
                    <Pencil size={14} />
                  </button>
                ) : (
                  <span style={{ fontSize: "0.75rem", color: "var(--text-muted)", fontStyle: "italic" }}>
                    (you)
                  </span>
                )}
              </td>
            </tr>
          ))}
        </tbody>
      </table>

      {editingUser && (
        <EditUserModal
          user={editingUser}
          onClose={() => setEditingUser(null)}
          onSuccess={() => {
            loadUsers();
            setEditingUser(null);
          }}
        />
      )}
    </div>
  );
}

// ============================================================================
// Edit User Modal
// ============================================================================

interface EditUserModalProps {
  user: UserResponse;
  onClose: () => void;
  onSuccess: () => void;
}

function EditUserModal({ user, onClose, onSuccess }: EditUserModalProps) {
  const { showToast } = useToast();
  const [newPassword, setNewPassword] = useState("");
  const [working, setWorking] = useState(false);
  const [confirmAction, setConfirmAction] = useState<{
    title: string;
    message: string;
    confirmText: string;
    confirmClass: string;
    action: () => void;
  } | null>(null);

  async function handleResetPassword() {
    if (!newPassword) {
      showToast("Password is required", "error");
      return;
    }
    if (newPassword.length < 4) {
      showToast("Password must be at least 4 characters", "error");
      return;
    }
    setWorking(true);
    try {
      await resetUserPassword(user.id, newPassword);
      showToast("Password reset successfully!", "success");
      onSuccess();
    } catch (err: any) {
      showToast("Failed to reset password: " + err.message, "error");
    } finally {
      setWorking(false);
    }
  }

  function showPromoteConfirm() {
    setConfirmAction({
      title: "Promote to Admin",
      message: `Are you sure you want to promote ${user.username} to admin?`,
      confirmText: "Promote",
      confirmClass: "btn-primary",
      action: async () => {
        setConfirmAction(null);
        setWorking(true);
        try {
          await promoteToAdmin(user.id);
          showToast("User promoted to admin!", "success");
          onSuccess();
        } catch (err: any) {
          showToast("Failed to promote user: " + err.message, "error");
        } finally {
          setWorking(false);
        }
      },
    });
  }

  function showDemoteConfirm() {
    setConfirmAction({
      title: "Demote from Admin",
      message: `Are you sure you want to demote ${user.username} to regular user?`,
      confirmText: "Demote",
      confirmClass: "btn-warning",
      action: async () => {
        setConfirmAction(null);
        setWorking(true);
        try {
          await demoteFromAdmin(user.id);
          showToast("User demoted to regular user!", "success");
          onSuccess();
        } catch (err: any) {
          showToast("Failed to demote user: " + err.message, "error");
        } finally {
          setWorking(false);
        }
      },
    });
  }

  function showToggleActiveConfirm() {
    const action = user.is_active ? "deactivate" : "activate";
    setConfirmAction({
      title: user.is_active ? "Deactivate User" : "Activate User",
      message: `Are you sure you want to ${action} ${user.username}?`,
      confirmText: user.is_active ? "Deactivate" : "Activate",
      confirmClass: user.is_active ? "btn-danger" : "btn-success",
      action: async () => {
        setConfirmAction(null);
        setWorking(true);
        try {
          if (user.is_active) {
            await deactivateUser(user.id);
            showToast("User deactivated!", "success");
          } else {
            await activateUser(user.id);
            showToast("User activated!", "success");
          }
          onSuccess();
        } catch (err: any) {
          showToast(`Failed to ${action} user: ` + err.message, "error");
        } finally {
          setWorking(false);
        }
      },
    });
  }

  return (
    <div className="modal-overlay" onClick={onClose}>
      <div className="modal-content" onClick={(e) => e.stopPropagation()}>
        <div className="modal-header">
          <h3>Manage User: {user.username}</h3>
          <button onClick={onClose} className="modal-close"><X size={20} /></button>
        </div>

        <div className="modal-body">
          {/* User Info */}
          <div style={{ marginBottom: "1.5rem", padding: "0.75rem", background: "var(--bg)", borderRadius: "8px" }}>
            <div style={{ display: "flex", justifyContent: "space-between", marginBottom: "0.5rem" }}>
              <span style={{ color: "var(--text-muted)", fontSize: "0.85rem" }}>Role:</span>
              <span style={{
                textTransform: "uppercase",
                fontSize: "0.85rem",
                color: user.role === "admin" ? "var(--accent)" : "var(--text-muted)"
              }}>
                {user.role}
              </span>
            </div>
            <div style={{ display: "flex", justifyContent: "space-between" }}>
              <span style={{ color: "var(--text-muted)", fontSize: "0.85rem" }}>Status:</span>
              <span style={{ fontSize: "0.85rem", color: user.is_active ? "var(--green)" : "var(--text-muted)" }}>
                {user.is_active ? "Active" : "Inactive"}
              </span>
            </div>
          </div>

          {/* Reset Password Section */}
          <div style={{ marginBottom: "1.5rem" }}>
            <h4 style={{ fontSize: "0.9rem", marginBottom: "0.75rem", color: "var(--text-muted)" }}>Reset Password</h4>
            <div className="form-group" style={{ marginBottom: "0.75rem" }}>
              <input
                type="password"
                value={newPassword}
                onChange={(e) => setNewPassword(e.target.value)}
                placeholder="Enter new password"
                disabled={working}
              />
            </div>
            <button
              onClick={handleResetPassword}
              disabled={working}
              className="btn btn-warning"
              style={{ width: "100%" }}
            >
              {working ? "Resetting..." : "Reset Password"}
            </button>
          </div>

          {/* Role Management Section */}
          <div style={{ marginBottom: "1.5rem" }}>
            <h4 style={{ fontSize: "0.9rem", marginBottom: "0.75rem", color: "var(--text-muted)" }}>Role Management</h4>
            {user.role !== "admin" ? (
              <button
                onClick={showPromoteConfirm}
                disabled={working}
                className="btn btn-primary"
                style={{ width: "100%" }}
              >
                {working ? "Promoting..." : "Promote to Admin"}
              </button>
            ) : (
              <button
                onClick={showDemoteConfirm}
                disabled={working}
                className="btn btn-warning"
                style={{ width: "100%" }}
              >
                {working ? "Demoting..." : "Demote to User"}
              </button>
            )}
          </div>

          {/* Activate/Deactivate Section */}
          <div>
            <h4 style={{ fontSize: "0.9rem", marginBottom: "0.75rem", color: "var(--text-muted)" }}>Account Status</h4>
            <button
              onClick={showToggleActiveConfirm}
              disabled={working}
              className={`btn ${user.is_active ? "btn-danger" : "btn-success"}`}
              style={{ width: "100%" }}
            >
              {working ? "Processing..." : user.is_active ? "Deactivate User" : "Activate User"}
            </button>
          </div>
        </div>

        {/* Confirmation Modal */}
        {confirmAction && (
          <ConfirmModal
            title={confirmAction.title}
            message={confirmAction.message}
            confirmText={confirmAction.confirmText}
            cancelText="Cancel"
            confirmClass={confirmAction.confirmClass}
            onConfirm={confirmAction.action}
            onCancel={() => setConfirmAction(null)}
          />
        )}
      </div>
    </div>
  );
}

