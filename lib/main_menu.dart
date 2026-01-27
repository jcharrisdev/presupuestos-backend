import 'package:flutter/material.dart';
import 'lista_presupuestos.dart';
import 'ahorro_meta.dart';
import 'calendario.dart';

class MainMenu extends StatelessWidget {
  final String firebaseUid;

  const MainMenu({
    Key? key,
    required this.firebaseUid,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Menú Principal'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () {
              Navigator.pop(context); // vuelve al login
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Usuario: $firebaseUid',
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 20),

          _menuItem(
            context,
            Icons.account_balance_wallet,
            'Presupuesto General',
                () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ListaPresupuestos(
                    firebaseUid: firebaseUid,
                  ),
                ),
              );
            },
          ),

          _menuItem(
            context,
            Icons.savings,
            'Ahorro Personal / Meta',
                () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => AhorroMetaScreen(
                    firebaseUid: firebaseUid,
                  ),
                ),
              );
            },
          ),

          _menuItem(
            context,
            Icons.calendar_today,
            'Calendario',
                () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => CalendarioScreen(),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _menuItem(
      BuildContext context,
      IconData icon,
      String label,
      VoidCallback onTap,
      ) {
    return Card(
      child: ListTile(
        leading: Icon(icon),
        title: Text(label),
        trailing: const Icon(Icons.arrow_forward),
        onTap: onTap,
      ),
    );
  }
}
