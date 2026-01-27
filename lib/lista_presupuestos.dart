import 'package:flutter/material.dart';
import 'crear_presupuesto.dart';
import 'presupuestos_service.dart';
import 'detalles_presupuesto.dart';

class ListaPresupuestos extends StatefulWidget {
  final String firebaseUid;

  const ListaPresupuestos({
    Key? key,
    required this.firebaseUid,
  }) : super(key: key);

  @override
  _ListaPresupuestosState createState() => _ListaPresupuestosState();
}

class _ListaPresupuestosState extends State<ListaPresupuestos> {
  List<dynamic> presupuestos = [];
  final PresupuestoService servicioPresupuestos = PresupuestoService();
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _cargarPresupuestos();
  }

  Future<void> _cargarPresupuestos() async {
    try {
      final datos =
      await servicioPresupuestos.obtenerPresupuestos(widget.firebaseUid);

      setState(() {
        presupuestos = datos;
        isLoading = false;
      });
    } catch (e) {
      setState(() {
        isLoading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al cargar presupuestos'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Lista de Presupuestos'),
      ),
      body: isLoading
          ? Center(child: CircularProgressIndicator())
          : presupuestos.isEmpty
          ? Center(child: Text('No hay presupuestos registrados'))
          : ListView.builder(
        itemCount: presupuestos.length,
        itemBuilder: (context, index) {
          final presupuesto = presupuestos[index];

          return ListTile(
            title: Text(presupuesto['nombre']),
            subtitle: Text(
              'Monto Total: \$${presupuesto['monto_total']}',
            ),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => DetallesPresupuesto(
                    presupuesto: presupuesto,
                    firebaseUid: widget.firebaseUid,
                  ),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => CrearPresupuesto(
                firebaseUid: widget.firebaseUid,
              ),
            ),
          );

          setState(() {
            isLoading = true;
            _cargarPresupuestos();
          });
        },
        child: Icon(Icons.add),
      ),
    );
  }
}
