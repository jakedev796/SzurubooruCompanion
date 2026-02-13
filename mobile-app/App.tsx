import React from "react";
import { NavigationContainer } from "@react-navigation/native";
import { createNativeStackNavigator } from "@react-navigation/native-stack";

import HomeScreen from "./src/screens/HomeScreen";
import SettingsScreen from "./src/screens/SettingsScreen";
import FolderWatchScreen from "./src/screens/FolderWatchScreen";

export type RootStackParamList = {
  Home: undefined;
  Settings: undefined;
  FolderWatch: undefined;
};

const Stack = createNativeStackNavigator<RootStackParamList>();

export default function App() {
  return (
    <NavigationContainer>
      <Stack.Navigator
        initialRouteName="Home"
        screenOptions={{
          headerStyle: { backgroundColor: "#14161a" },
          headerTintColor: "#d4d4d8",
          contentStyle: { backgroundColor: "#0f1117" },
        }}
      >
        <Stack.Screen name="Home" component={HomeScreen} options={{ title: "Szurubooru Companion" }} />
        <Stack.Screen name="Settings" component={SettingsScreen} options={{ title: "Settings" }} />
        <Stack.Screen name="FolderWatch" component={FolderWatchScreen} options={{ title: "Folder Watch" }} />
      </Stack.Navigator>
    </NavigationContainer>
  );
}
