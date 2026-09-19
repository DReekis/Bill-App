

## Quick Build Commands

### Android
```bash
cd app
flutter pub get
flutter build apk --release      
flutter build appbundle --release #for playstore
```

### Windows Desktop (x64)
```bash
cd app
flutter build windows --release  
```

### Web
```bash
cd app
flutter build web --release      

### Backend (Sync & Admin Server)
```bash
cd backend
npm install
npx prisma db push
npm run build && npm start
```

### Run Tests
```bash
cd app
flutter test
```

---
