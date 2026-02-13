import React, { useEffect, useState } from "react";
import { View, Text, TextInput, TouchableOpacity, StyleSheet, Alert } from "react-native";
import { loadConfig, saveConfig, CccConfig } from "../services/api";

export default function SettingsScreen() {
  const [baseUrl, setBaseUrl] = useState("");
  const [apiKey, setApiKey] = useState("");

  useEffect(() => {
    loadConfig().then((cfg) => {
      setBaseUrl(cfg.baseUrl);
      setApiKey(cfg.apiKey);
    });
  }, []);

  async function handleSave() {
    const cfg: CccConfig = {
      baseUrl: baseUrl.replace(/\/+$/, ""),
      apiKey: apiKey.trim(),
    };
    await saveConfig(cfg);
    Alert.alert("Saved", "CCC connection settings updated.");
  }

  return (
    <View style={styles.container}>
      <Text style={styles.label}>CCC Base URL</Text>
      <TextInput
        style={styles.input}
        value={baseUrl}
        onChangeText={setBaseUrl}
        placeholder="http://192.168.1.100:8000"
        placeholderTextColor="#52525b"
        autoCapitalize="none"
        autoCorrect={false}
      />

      <Text style={styles.label}>API Key (optional)</Text>
      <TextInput
        style={styles.input}
        value={apiKey}
        onChangeText={setApiKey}
        placeholder="Leave blank if not required"
        placeholderTextColor="#52525b"
        secureTextEntry
      />

      <TouchableOpacity style={styles.btn} onPress={handleSave}>
        <Text style={styles.btnText}>Save</Text>
      </TouchableOpacity>
    </View>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, padding: 24 },
  label: { color: "#71717a", fontSize: 12, marginBottom: 4, textTransform: "uppercase", letterSpacing: 0.5 },
  input: {
    backgroundColor: "#181a20",
    borderWidth: 1,
    borderColor: "#2a2d36",
    borderRadius: 8,
    padding: 12,
    color: "#d4d4d8",
    fontSize: 14,
    marginBottom: 16,
  },
  btn: {
    backgroundColor: "#6366f1",
    borderRadius: 8,
    paddingVertical: 14,
    alignItems: "center",
    marginTop: 8,
  },
  btnText: { color: "#fff", fontSize: 15, fontWeight: "600" },
});
