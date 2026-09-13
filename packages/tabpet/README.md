# tabpet

A companion for the iOS tab bar in your Expo app: it seats on the native bar, runs when you switch tabs, chases your finger, and takes the long way round the pill. iOS 15.1+ only.

## Install

```bash
npx expo install react-native-tabpet react-native-reanimated react-native-gesture-handler react-native-worklets expo-image react-native-safe-area-context
npx expo prebuild --clean --platform ios
```

Wrap the root in `CompanionProvider`, mount one `CompanionPerch` beside the tab navigator, and pass it the active tab index. The integration guide has the whole thing.

The root entry bundles all six sprite sheets (~13MB). To ship one animal, import from `react-native-tabpet/bare` and register only `react-native-tabpet/animals/<id>`.

## Links

- [Repository README](https://github.com/Lakshay1800/tabpet#readme)
- [Integration guide](https://github.com/Lakshay1800/tabpet/blob/main/docs/integration.md)
- [API reference](https://github.com/Lakshay1800/tabpet/blob/main/docs/api.md)
- [Profiles and geometry](https://github.com/Lakshay1800/tabpet/blob/main/docs/profiles.md)
- [Making a new animal](https://github.com/Lakshay1800/tabpet/blob/main/docs/art-pipeline.md)

## License

- Code: [MIT](https://github.com/Lakshay1800/tabpet/blob/main/LICENSE)
- Sprite sheets (six bundled animals): [CC BY 4.0](https://github.com/Lakshay1800/tabpet/blob/main/assets/LICENSE-ART.md)
