# 3D Car Model Asset

## Place your car.glb file here

This folder is configured to load the 3D car model in the Flutter app.

### Instructions:
1. Copy your `car.glb` file to this directory
2. The file should be named exactly: `car.glb`
3. Run `flutter pub get` to update dependencies
4. Build and run your app

### Model Requirements:
- Format: GLB (GL Transmission Format Binary)
- Recommended size: Under 5MB for mobile performance
- Recommended: Centered at origin for best viewing

### Alternative (for testing):
If you don't have a GLB file yet, you can use a sample model from the web by modifying the `src` in `main.dart` to:
```
src: 'https://modelviewer.dev/shared-assets/models/Toy%20Car.glb'