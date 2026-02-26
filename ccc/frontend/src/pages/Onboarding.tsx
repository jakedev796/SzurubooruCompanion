import { useState, useEffect, useCallback } from "react";
import { useNavigate } from "react-router-dom";
import {
  ChevronRight,
  ChevronLeft,
  ChevronDown,
  Check,
  ExternalLink,
  Loader,
} from "lucide-react";
import {
  createSetupAdmin,
  fetchSzuruCategories,
  updateMyConfig,
  updateCategoryMappings,
  fetchSupportedSites,
  setJWT,
  SiteInfo,
} from "../api";
import { useAuth } from "../contexts/AuthContext";
import { useToast } from "../contexts/ToastContext";

const ONBOARDING_DISMISSED_KEY = "ccc_onboarding_dismissed";

// ============================================================================
// Types
// ============================================================================

interface StepDef {
  key: string;
  label: string;
}

interface SharedState {
  szuruUrl: string;
  szuruUsername: string;
  szuruToken: string;
  szuruSkipped: boolean;
  szuruCategories: Array<{ name: string; color: string; order: number }>;
}

// ============================================================================
// Onboarding (default export)
// ============================================================================

export default function Onboarding({ variant }: { variant: "admin" | "user" }) {
  const adminSteps: StepDef[] = [
    { key: "welcome", label: "Welcome" },
    { key: "account", label: "Account" },
    { key: "szurubooru", label: "Szurubooru" },
    { key: "categories", label: "Categories" },
    { key: "sites", label: "Sites" },
    { key: "next-steps", label: "Next Steps" },
  ];

  const userSteps: StepDef[] = [
    { key: "szurubooru", label: "Szurubooru" },
    { key: "categories", label: "Categories" },
    { key: "sites", label: "Sites" },
    { key: "next-steps", label: "Next Steps" },
  ];

  const steps = variant === "admin" ? adminSteps : userSteps;

  const [currentStep, setCurrentStep] = useState(0);
  const [completedSteps, setCompletedSteps] = useState<Set<number>>(new Set());
  const [shared, setShared] = useState<SharedState>({
    szuruUrl: "",
    szuruUsername: "",
    szuruToken: "",
    szuruSkipped: false,
    szuruCategories: [],
  });

  function advance(skipCategories?: boolean) {
    setCompletedSteps((prev) => new Set([...prev, currentStep]));
    setCurrentStep((prev) => {
      let next = prev + 1;
      if (steps[next]?.key === "categories" && (shared.szuruSkipped || skipCategories)) {
        setCompletedSteps((p) => new Set([...p, next]));
        next += 1;
      }
      return next;
    });
  }

  function goBack() {
    let prev = currentStep - 1;

    // Skip back over Categories if Szurubooru was skipped
    if (shared.szuruSkipped && steps[prev]?.key === "categories") {
      prev -= 1;
    }

    if (prev >= 0) {
      setCurrentStep(prev);
    }
  }

  const stepKey = steps[currentStep]?.key;

  return (
    <div className="onboarding-container">
      <div className="onboarding-card">
        {/* Progress stepper */}
        <div className="onboarding-progress">
          {steps.map((step, i) => (
            <div
              key={step.key}
              className={`onboarding-progress-step${i === currentStep ? " active" : ""}${completedSteps.has(i) ? " completed" : ""}`}
            >
              <div className="onboarding-progress-dot">
                {completedSteps.has(i) ? <Check size={14} /> : i + 1}
              </div>
              <span className="onboarding-progress-label">{step.label}</span>
            </div>
          ))}
        </div>

        {/* Step content */}
        <div className="onboarding-step">
          {stepKey === "welcome" && (
            <WelcomeStep onNext={advance} />
          )}
          {stepKey === "account" && (
            <CreateAdminStep onNext={advance} onBack={goBack} />
          )}
          {stepKey === "szurubooru" && (
            <SzuruboruStep
              shared={shared}
              setShared={setShared}
              onNext={advance}
              onBack={goBack}
              showBack={currentStep > 0}
            />
          )}
          {stepKey === "categories" && (
            <CategoryMappingStep
              shared={shared}
              onNext={advance}
              onBack={goBack}
            />
          )}
          {stepKey === "sites" && (
            <SiteCredentialsStep onNext={advance} onBack={goBack} />
          )}
          {stepKey === "next-steps" && (
            <NextStepsStep onBack={goBack} />
          )}
        </div>
      </div>
    </div>
  );
}

// ============================================================================
// WelcomeStep
// ============================================================================

function WelcomeStep({ onNext }: { onNext: () => void }) {
  return (
    <>
      <h2 className="onboarding-step-header">Welcome to SzurubooruCompanion</h2>
      <p>
        This wizard will help you set up your companion instance. Here is what
        we will configure:
      </p>
      <ul className="onboarding-checklist">
        <li>Create an admin account</li>
        <li>Connect to your Szurubooru instance</li>
        <li>Map tag categories between sources and Szurubooru</li>
        <li>Optionally configure site credentials for downloading</li>
      </ul>
      <p>You can always change these settings later from the Settings page.</p>
      <div className="onboarding-actions">
        <button className="btn btn-primary" onClick={onNext}>
          Get Started <ChevronRight size={16} />
        </button>
      </div>
    </>
  );
}

// ============================================================================
// CreateAdminStep
// ============================================================================

function CreateAdminStep({
  onNext,
  onBack,
}: {
  onNext: () => void;
  onBack: () => void;
}) {
  const auth = useAuth();
  const { showToast } = useToast();
  const [username, setUsername] = useState("admin");
  const [password, setPassword] = useState("");
  const [confirmPassword, setConfirmPassword] = useState("");
  const [saving, setSaving] = useState(false);

  async function handleSubmit() {
    if (password.length < 8) {
      showToast("Password must be at least 8 characters", "error");
      return;
    }
    if (password !== confirmPassword) {
      showToast("Passwords do not match", "error");
      return;
    }

    setSaving(true);
    try {
      const res = await createSetupAdmin(username, password);
      setJWT(res.access_token);
      await auth.login(username, password);
      showToast("Admin account created!", "success");
      onNext();
    } catch (err: any) {
      showToast(err.message || "Failed to create admin account", "error");
    } finally {
      setSaving(false);
    }
  }

  return (
    <>
      <h2 className="onboarding-step-header">Create Admin Account</h2>
      <p>Set up the first administrator account for this instance.</p>
      <div className="settings-form">
        <div className="form-group">
          <label>Username</label>
          <input
            type="text"
            value={username}
            onChange={(e) => setUsername(e.target.value.replace(/\s/g, ""))}
            placeholder="admin"
          />
        </div>
        <div className="form-group">
          <label>Password</label>
          <input
            type="password"
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            placeholder="Minimum 8 characters"
          />
          <span className="form-hint">Must be at least 8 characters</span>
        </div>
        <div className="form-group">
          <label>Confirm Password</label>
          <input
            type="password"
            value={confirmPassword}
            onChange={(e) => setConfirmPassword(e.target.value)}
            placeholder="Repeat password"
          />
        </div>
      </div>
      <div className="onboarding-actions">
        <button className="btn btn-ghost" onClick={onBack}>
          <ChevronLeft size={16} /> Back
        </button>
        <button
          className="btn btn-primary"
          onClick={handleSubmit}
          disabled={saving || !username || !password || !confirmPassword}
        >
          {saving ? (
            <>
              <Loader size={16} className="spinning" /> Creating...
            </>
          ) : (
            <>
              Create Account <ChevronRight size={16} />
            </>
          )}
        </button>
      </div>
    </>
  );
}

// ============================================================================
// SzuruboruStep
// ============================================================================

function SzuruboruStep({
  shared,
  setShared,
  onNext,
  onBack,
  showBack,
}: {
  shared: SharedState;
  setShared: React.Dispatch<React.SetStateAction<SharedState>>;
  onNext: (skipCategories?: boolean) => void;
  onBack: () => void;
  showBack: boolean;
}) {
  const { showToast } = useToast();
  const [testing, setTesting] = useState(false);
  const [testPassed, setTestPassed] = useState(false);
  const [saving, setSaving] = useState(false);

  async function handleTest() {
    if (!shared.szuruUrl || !shared.szuruUsername || !shared.szuruToken) {
      showToast("Please fill in all fields before testing", "error");
      return;
    }

    setTesting(true);
    setTestPassed(false);
    try {
      const result = await fetchSzuruCategories(
        shared.szuruUrl,
        shared.szuruUsername,
        shared.szuruToken
      );
      if (result.error) {
        showToast("Connection failed: " + result.error, "error");
      } else if (result.results) {
        setShared((prev) => ({
          ...prev,
          szuruCategories: result.results!.sort((a, b) => a.order - b.order),
        }));
        setTestPassed(true);
        showToast(
          "Connection successful! Found " + result.results.length + " categories.",
          "success"
        );
      }
    } catch (err: any) {
      showToast("Connection failed: " + err.message, "error");
    } finally {
      setTesting(false);
    }
  }

  async function handleSave() {
    setSaving(true);
    try {
      await updateMyConfig({
        szuru_url: shared.szuruUrl,
        szuru_username: shared.szuruUsername,
        szuru_token: shared.szuruToken,
      });
      showToast("Szurubooru configuration saved!", "success");
      onNext();
    } catch (err: any) {
      showToast("Failed to save: " + err.message, "error");
    } finally {
      setSaving(false);
    }
  }

  function handleSkip() {
    setShared((prev) => ({ ...prev, szuruSkipped: true }));
    onNext(true);
  }

  return (
    <>
      <h2 className="onboarding-step-header">Connect Szurubooru</h2>
      <p>
        Connect to your Szurubooru instance. You can find your API token in
        Szurubooru under Account &gt; Login tokens.
      </p>
      <div className="settings-form">
        <div className="form-group">
          <label>Szurubooru URL</label>
          <input
            type="text"
            value={shared.szuruUrl}
            onChange={(e) =>
              setShared((prev) => ({ ...prev, szuruUrl: e.target.value }))
            }
            placeholder="http://192.168.1.100:8080"
          />
          <span className="form-hint">
            Internal URL used for API calls (can be a local IP)
          </span>
        </div>
        <div className="form-group">
          <label>Username</label>
          <input
            type="text"
            value={shared.szuruUsername}
            onChange={(e) =>
              setShared((prev) => ({ ...prev, szuruUsername: e.target.value }))
            }
            placeholder="Your Szurubooru username"
          />
        </div>
        <div className="form-group">
          <label>API Token</label>
          <input
            type="password"
            value={shared.szuruToken}
            onChange={(e) =>
              setShared((prev) => ({ ...prev, szuruToken: e.target.value }))
            }
            placeholder="Szurubooru API token"
          />
        </div>
        <button
          className="btn btn-secondary btn-sm"
          onClick={handleTest}
          disabled={testing || !shared.szuruUrl || !shared.szuruUsername || !shared.szuruToken}
        >
          {testing ? (
            <>
              <Loader size={14} className="spinning" /> Testing...
            </>
          ) : testPassed ? (
            <>
              <Check size={14} /> Connection OK
            </>
          ) : (
            "Test Connection"
          )}
        </button>
      </div>
      <div className="onboarding-actions">
        {showBack && (
          <button className="btn btn-ghost" onClick={onBack}>
            <ChevronLeft size={16} /> Back
          </button>
        )}
        <button className="btn btn-ghost" onClick={handleSkip}>
          Skip for now
        </button>
        <button
          className="btn btn-primary"
          onClick={handleSave}
          disabled={!testPassed || saving}
        >
          {saving ? (
            <>
              <Loader size={16} className="spinning" /> Saving...
            </>
          ) : (
            <>
              Save &amp; Continue <ChevronRight size={16} />
            </>
          )}
        </button>
      </div>
    </>
  );
}

// ============================================================================
// CategoryMappingStep
// ============================================================================

const SOURCE_CATEGORIES = ["general", "artist", "character", "copyright", "meta"];

function CategoryMappingStep({
  shared,
  onNext,
  onBack,
}: {
  shared: SharedState;
  onNext: () => void;
  onBack: () => void;
}) {
  const { showToast } = useToast();
  const [categories, setCategories] = useState<
    Array<{ name: string; color: string; order: number }>
  >([]);
  const [mappings, setMappings] = useState<Record<string, string>>({});
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);

  const autoMap = useCallback(
    (szuruCats: Array<{ name: string; color: string; order: number }>) => {
      const auto: Record<string, string> = {};
      for (const src of SOURCE_CATEGORIES) {
        const match = szuruCats.find(
          (c) => c.name.toLowerCase() === src.toLowerCase()
        );
        if (match) {
          auto[src] = match.name;
        }
      }
      setMappings(auto);
    },
    []
  );

  useEffect(() => {
    // Use categories already fetched during the Szurubooru test step
    if (shared.szuruCategories.length > 0) {
      setCategories(shared.szuruCategories);
      autoMap(shared.szuruCategories);
      setLoading(false);
      return;
    }

    // Fallback: fetch again if we don't have them
    if (!shared.szuruUrl || !shared.szuruUsername || !shared.szuruToken) {
      setLoading(false);
      return;
    }

    fetchSzuruCategories(shared.szuruUrl, shared.szuruUsername, shared.szuruToken)
      .then((result) => {
        if (result.results) {
          const sorted = result.results.sort((a, b) => a.order - b.order);
          setCategories(sorted);
          autoMap(sorted);
        }
      })
      .catch((err: any) => {
        showToast("Failed to fetch categories: " + err.message, "error");
      })
      .finally(() => setLoading(false));
  }, [shared.szuruCategories, shared.szuruUrl, shared.szuruUsername, shared.szuruToken, autoMap, showToast]);

  async function handleSave() {
    setSaving(true);
    try {
      await updateCategoryMappings(mappings);
      showToast("Category mappings saved!", "success");
      onNext();
    } catch (err: any) {
      showToast("Failed to save mappings: " + err.message, "error");
    } finally {
      setSaving(false);
    }
  }

  if (loading) {
    return (
      <>
        <h2 className="onboarding-step-header">Map Tag Categories</h2>
        <p>
          <Loader size={16} className="spinning" /> Loading categories...
        </p>
      </>
    );
  }

  return (
    <>
      <h2 className="onboarding-step-header">Map Tag Categories</h2>
      <p>
        Map source tag categories to your Szurubooru categories. Matching names
        have been auto-mapped. Adjust as needed.
      </p>
      <div className="onboarding-mappings">
        <div className="settings-form">
          {SOURCE_CATEGORIES.map((src) => (
            <div key={src} className="form-group-row">
              <label style={{ textTransform: "capitalize" }}>{src}</label>
              {categories.length > 0 ? (
                <select
                  value={mappings[src] || ""}
                  onChange={(e) =>
                    setMappings((prev) => ({ ...prev, [src]: e.target.value }))
                  }
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
                  value={mappings[src] || ""}
                  onChange={(e) =>
                    setMappings((prev) => ({ ...prev, [src]: e.target.value }))
                  }
                  placeholder={`e.g., ${src}`}
                />
              )}
            </div>
          ))}
        </div>
      </div>
      <div className="onboarding-actions">
        <button className="btn btn-ghost" onClick={onBack}>
          <ChevronLeft size={16} /> Back
        </button>
        <button className="btn btn-ghost" onClick={onNext}>
          Skip
        </button>
        <button
          className="btn btn-primary"
          onClick={handleSave}
          disabled={saving}
        >
          {saving ? (
            <>
              <Loader size={16} className="spinning" /> Saving...
            </>
          ) : (
            <>
              Save &amp; Continue <ChevronRight size={16} />
            </>
          )}
        </button>
      </div>
    </>
  );
}

// ============================================================================
// SiteCredentialsStep
// ============================================================================

function SiteCredentialsStep({
  onNext,
  onBack,
}: {
  onNext: () => void;
  onBack: () => void;
}) {
  const { showToast } = useToast();
  const [sites, setSites] = useState<SiteInfo[]>([]);
  const [creds, setCreds] = useState<Record<string, Record<string, string>>>({});
  const [expandedSite, setExpandedSite] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    fetchSupportedSites()
      .then((data) => setSites(data))
      .catch((err: any) => {
        showToast("Failed to load sites: " + err.message, "error");
      })
      .finally(() => setLoading(false));
  }, [showToast]);

  function updateCred(site: string, field: string, value: string) {
    setCreds((prev) => ({
      ...prev,
      [site]: { ...(prev[site] || {}), [field]: value },
    }));
  }

  function isFieldPassword(field: string): boolean {
    return (
      field.includes("password") ||
      field.includes("secret") ||
      field.includes("token")
    );
  }

  async function handleSave() {
    // Filter out sites/fields with empty values
    const filtered: Record<string, Record<string, string>> = {};
    for (const [site, fields] of Object.entries(creds)) {
      const nonEmpty: Record<string, string> = {};
      for (const [key, val] of Object.entries(fields)) {
        if (val.trim()) {
          nonEmpty[key] = val.trim();
        }
      }
      if (Object.keys(nonEmpty).length > 0) {
        filtered[site] = nonEmpty;
      }
    }

    // If nothing entered, just advance
    if (Object.keys(filtered).length === 0) {
      onNext();
      return;
    }

    setSaving(true);
    try {
      await updateMyConfig({ site_credentials: filtered });
      showToast("Site credentials saved!", "success");
      onNext();
    } catch (err: any) {
      showToast("Failed to save credentials: " + err.message, "error");
    } finally {
      setSaving(false);
    }
  }

  if (loading) {
    return (
      <>
        <h2 className="onboarding-step-header">Site Credentials</h2>
        <p>
          <Loader size={16} className="spinning" /> Loading supported sites...
        </p>
      </>
    );
  }

  return (
    <>
      <h2 className="onboarding-step-header">Site Credentials</h2>
      <p>
        Optionally configure credentials for sites that require authentication
        to download. All credentials are encrypted at rest.
      </p>
      <div className="onboarding-sites">
        {sites.map((site) => (
          <div key={site.name} className="accordion">
            <button
              className="accordion-header"
              onClick={() =>
                setExpandedSite(expandedSite === site.name ? null : site.name)
              }
            >
              <span style={{ textTransform: "capitalize", fontWeight: 500 }}>
                {site.name}
              </span>
              <ChevronDown
                size={16}
                className={`accordion-icon${expandedSite === site.name ? " open" : ""}`}
              />
            </button>
            {expandedSite === site.name && (
              <div className="accordion-content">
                <div className="settings-form">
                  {site.fields.map((field) => (
                    <div key={field} className="form-group">
                      <label style={{ textTransform: "capitalize" }}>
                        {field.replace(/_/g, " ").replace(/-/g, " ")}
                      </label>
                      {field === "cookies" ? (
                        <textarea
                          value={creds[site.name]?.[field] || ""}
                          onChange={(e) =>
                            updateCred(site.name, field, e.target.value)
                          }
                          placeholder="Netscape cookie format"
                          rows={3}
                          style={{
                            fontFamily: "Monaco, Courier New, monospace",
                            fontSize: "0.8rem",
                          }}
                        />
                      ) : (
                        <input
                          type={isFieldPassword(field) ? "password" : "text"}
                          value={creds[site.name]?.[field] || ""}
                          onChange={(e) =>
                            updateCred(site.name, field, e.target.value)
                          }
                        />
                      )}
                    </div>
                  ))}
                </div>
              </div>
            )}
          </div>
        ))}
      </div>
      <div className="onboarding-actions">
        <button className="btn btn-ghost" onClick={onBack}>
          <ChevronLeft size={16} /> Back
        </button>
        <button
          className="btn btn-primary"
          onClick={handleSave}
          disabled={saving}
        >
          {saving ? (
            <>
              <Loader size={16} className="spinning" /> Saving...
            </>
          ) : (
            <>
              Save &amp; Continue <ChevronRight size={16} />
            </>
          )}
        </button>
      </div>
    </>
  );
}

// ============================================================================
// NextStepsStep
// ============================================================================

const REPO_URL = "https://github.com/jakedev796/SzurubooruCompanion";

function NextStepsStep({ onBack }: { onBack: () => void }) {
  const navigate = useNavigate();

  function handleFinish() {
    localStorage.setItem(ONBOARDING_DISMISSED_KEY, "true");
    navigate("/");
  }

  return (
    <>
      <h2 className="onboarding-step-header">You are all set!</h2>
      <p>
        Your instance is configured. Here are some optional next steps to get
        the most out of SzurubooruCompanion:
      </p>
      <div className="onboarding-next-steps">
        <div className="card">
          <h3>Browser Extension</h3>
          <p>
            Upload images directly from supported sites with a single click.
            Available for Chrome and Firefox.
          </p>
          <a
            href={`${REPO_URL}/releases`}
            target="_blank"
            rel="noopener noreferrer"
            className="btn btn-secondary btn-sm"
          >
            Download <ExternalLink size={14} />
          </a>
        </div>
        <div className="card">
          <h3>Mobile App</h3>
          <p>
            Browse and manage your Szurubooru library from your Android device.
          </p>
          <a
            href={`${REPO_URL}/releases`}
            target="_blank"
            rel="noopener noreferrer"
            className="btn btn-secondary btn-sm"
          >
            Download <ExternalLink size={14} />
          </a>
        </div>
        <div className="card">
          <h3>Documentation</h3>
          <p>
            Read the full documentation for configuration options, API usage,
            and more.
          </p>
          <a
            href={`${REPO_URL}/tree/main/docs`}
            target="_blank"
            rel="noopener noreferrer"
            className="btn btn-secondary btn-sm"
          >
            View Docs <ExternalLink size={14} />
          </a>
        </div>
      </div>
      <div className="onboarding-actions">
        <button className="btn btn-ghost" onClick={onBack}>
          <ChevronLeft size={16} /> Back
        </button>
        <button className="btn btn-primary" onClick={handleFinish}>
          Go to Dashboard <ChevronRight size={16} />
        </button>
      </div>
    </>
  );
}
