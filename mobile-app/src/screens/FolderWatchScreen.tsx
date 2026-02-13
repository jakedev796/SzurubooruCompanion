import React, { useEffect, useState } from "react";
import { View, Text, FlatList, TouchableOpacity, StyleSheet, Alert } from "react-native";
import {
  pickDirectory,
  errorCodes,
  isErrorWithCode,
} from "@react-native-documents/picker";
import { getWatchedFolders, setWatchedFolders } from "../services/folderWatch";

export default function FolderWatchScreen() {
  const [folders, setFolders] = useState<string[]>([]);

  useEffect(() => {
    getWatchedFolders().then(setFolders);
  }, []);

  async function handleAdd() {
    try {
      // Android: pick a directory (SAF).
      const { uri } = await pickDirectory({ requestLongTermAccess: false });
      if (uri) {
        const updated = [...folders, uri];
        await setWatchedFolders(updated);
        setFolders(updated);
      }
    } catch (err: unknown) {
      if (!(isErrorWithCode(err) && err.code === errorCodes.OPERATION_CANCELED)) {
        Alert.alert("Error", err instanceof Error ? err.message : String(err));
      }
    }
  }

  async function handleRemove(index: number) {
    const updated = folders.filter((_, i) => i !== index);
    await setWatchedFolders(updated);
    setFolders(updated);
  }

  return (
    <View style={styles.container}>
      <Text style={styles.hint}>
        Media files added to these folders will be uploaded to the CCC automatically (AI tagging only, no URL parsing).
      </Text>

      <FlatList
        data={folders}
        keyExtractor={(_, i) => String(i)}
        renderItem={({ item, index }) => (
          <View style={styles.row}>
            <Text style={styles.path} numberOfLines={1}>
              {item}
            </Text>
            <TouchableOpacity onPress={() => handleRemove(index)}>
              <Text style={styles.remove}>Remove</Text>
            </TouchableOpacity>
          </View>
        )}
        ListEmptyComponent={
          <Text style={styles.empty}>No folders configured yet.</Text>
        }
      />

      <TouchableOpacity style={styles.btn} onPress={handleAdd}>
        <Text style={styles.btnText}>Add Folder</Text>
      </TouchableOpacity>
    </View>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, padding: 24 },
  hint: { color: "#71717a", fontSize: 13, marginBottom: 20, lineHeight: 18 },
  row: {
    flexDirection: "row",
    alignItems: "center",
    backgroundColor: "#181a20",
    borderWidth: 1,
    borderColor: "#2a2d36",
    borderRadius: 8,
    padding: 12,
    marginBottom: 8,
  },
  path: { flex: 1, color: "#d4d4d8", fontSize: 13 },
  remove: { color: "#ef4444", fontSize: 13, fontWeight: "600", marginLeft: 12 },
  empty: { color: "#52525b", fontSize: 13, textAlign: "center", marginVertical: 32 },
  btn: {
    backgroundColor: "#6366f1",
    borderRadius: 8,
    paddingVertical: 14,
    alignItems: "center",
    marginTop: 12,
  },
  btnText: { color: "#fff", fontSize: 15, fontWeight: "600" },
});
