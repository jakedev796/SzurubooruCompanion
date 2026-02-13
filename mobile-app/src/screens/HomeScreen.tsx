import React, { useEffect, useState } from "react";
import { View, Text, StyleSheet, TouchableOpacity, Alert } from "react-native";
import type { NativeStackScreenProps } from "@react-navigation/native-stack";
import type { RootStackParamList } from "../../App";
import { registerShareListener, clearShareListener, ShareResult } from "../services/shareHandler";
import { scanAndUpload } from "../services/folderWatch";

type Props = NativeStackScreenProps<RootStackParamList, "Home">;

export default function HomeScreen({ navigation }: Props) {
  const [lastResult, setLastResult] = useState<string | null>(null);

  useEffect(() => {
    registerShareListener((r: ShareResult) => {
      if (r.success) {
        setLastResult(`Queued job: ${r.jobId}`);
      } else {
        setLastResult(`Error: ${r.error}`);
      }
    });
    return () => clearShareListener();
  }, []);

  async function handleScanNow() {
    try {
      const count = await scanAndUpload();
      Alert.alert("Folder Scan", `Uploaded ${count} new file(s).`);
    } catch (err: any) {
      Alert.alert("Error", err.message);
    }
  }

  return (
    <View style={styles.container}>
      <Text style={styles.title}>Szurubooru Companion</Text>
      <Text style={styles.subtitle}>
        Share a URL or media from any app to send it to the CCC for processing.
      </Text>

      {lastResult && (
        <View style={styles.resultBox}>
          <Text style={styles.resultText}>{lastResult}</Text>
        </View>
      )}

      <TouchableOpacity style={styles.btn} onPress={handleScanNow}>
        <Text style={styles.btnText}>Scan Watched Folders Now</Text>
      </TouchableOpacity>

      <TouchableOpacity
        style={[styles.btn, styles.btnSecondary]}
        onPress={() => navigation.navigate("FolderWatch")}
      >
        <Text style={styles.btnText}>Manage Watched Folders</Text>
      </TouchableOpacity>

      <TouchableOpacity
        style={[styles.btn, styles.btnSecondary]}
        onPress={() => navigation.navigate("Settings")}
      >
        <Text style={styles.btnText}>Settings</Text>
      </TouchableOpacity>
    </View>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, padding: 24 },
  title: { color: "#d4d4d8", fontSize: 22, fontWeight: "700", marginBottom: 8 },
  subtitle: { color: "#71717a", fontSize: 14, marginBottom: 24, lineHeight: 20 },
  resultBox: {
    backgroundColor: "#181a20",
    borderWidth: 1,
    borderColor: "#2a2d36",
    borderRadius: 8,
    padding: 12,
    marginBottom: 20,
  },
  resultText: { color: "#d4d4d8", fontSize: 13 },
  btn: {
    backgroundColor: "#6366f1",
    borderRadius: 8,
    paddingVertical: 14,
    alignItems: "center",
    marginBottom: 12,
  },
  btnSecondary: { backgroundColor: "#1e2028", borderWidth: 1, borderColor: "#2a2d36" },
  btnText: { color: "#d4d4d8", fontSize: 15, fontWeight: "600" },
});
