// firebase-messaging-sw.js — recibe push en segundo plano (pestaña cerrada o
// en background). Los valores de abajo son el config público del cliente del
// proyecto Firebase "salary-bi" (no son secretos, van en el navegador).
importScripts('https://www.gstatic.com/firebasejs/10.14.1/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.14.1/firebase-messaging-compat.js');

firebase.initializeApp({
  apiKey: 'AIzaSyB_8Nq2ZvHUq98UgK3KXmMaUOlJQhnN_aw',
  authDomain: 'salary-bi.firebaseapp.com',
  projectId: 'salary-bi',
  storageBucket: 'salary-bi.firebasestorage.app',
  messagingSenderId: '750057422826',
  appId: '1:750057422826:web:567c937283dc0969a4fc93',
});

const messaging = firebase.messaging();

// El payload llega como "notification" (no "data"), así que el navegador ya
// la muestra solo — no hace falta un handler explícito de background aquí.
