import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'theme/app_theme.dart';
import 'services/api_client.dart';
import 'dart:convert';

class DebugLogsScreen extends StatefulWidget {
  const DebugLogsScreen({Key? key}) : super(key: key);

  @override
  State<DebugLogsScreen> createState() => _DebugLogsScreenState();
}

class _DebugLogsScreenState extends State<DebugLogsScreen> {
  static const _secret = 'salarying_logs_2025';

  List<dynamic> _logs = [];
  int _total = 0;
  bool _loading = true;
  String? _error;
  String _nivelFiltro = 'todos';
  final _uidCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _uidCtrl.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    setState(() { _loading = true; _error = null; });
    try {
      var path = '/logs?secret=$_secret&limit=80';
      if (_nivelFiltro != 'todos') path += '&nivel=$_nivelFiltro';
      if (_uidCtrl.text.trim().isNotEmpty) path += '&uid=${Uri.encodeComponent(_uidCtrl.text.trim())}';
      final res = await ApiClient.get(path);
      if (res.statusCode != 200) {
        setState(() { _error = 'Error ${res.statusCode}: ${res.body}'; _loading = false; });
        return;
      }
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      setState(() {
        _logs  = data['logs'] as List? ?? [];
        _total = data['total'] as int? ?? 0;
        _loading = false;
      });
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _limpiarViejos() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text('Limpiar logs', style: TextStyle(color: AppTheme.textPrimary)),
        content: const Text('Elimina logs de más de 7 días. ¿Continuar?',
            style: TextStyle(color: AppTheme.textSecondary)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Limpiar', style: TextStyle(color: AppTheme.danger)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ApiClient.delete('/logs?secret=$_secret');
      _cargar();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Logs viejos eliminados')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: AppTheme.danger));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.surface,
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Logs del servidor', style: TextStyle(fontSize: 16)),
          if (!_loading)
            Text('$_total errores en total · mostrando ${_logs.length}',
                style: const TextStyle(color: AppTheme.textMuted, fontSize: 11)),
        ]),
        actions: [
          IconButton(icon: const Icon(Icons.delete_outline, color: AppTheme.danger),
              onPressed: _limpiarViejos, tooltip: 'Limpiar logs viejos'),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _cargar),
        ],
      ),
      body: Column(children: [
        // ── Filtros ──────────────────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            border: Border(bottom: BorderSide(color: AppTheme.border)),
          ),
          child: Row(children: [
            // Nivel
            Expanded(child: DropdownButtonFormField<String>(
              value: _nivelFiltro,
              dropdownColor: AppTheme.surfaceAlt,
              decoration: const InputDecoration(
                  labelText: 'Nivel', isDense: true,
                  contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 6)),
              style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13),
              items: const [
                DropdownMenuItem(value: 'todos', child: Text('Todos')),
                DropdownMenuItem(value: 'error', child: Text('Error')),
                DropdownMenuItem(value: 'warn',  child: Text('Warn')),
                DropdownMenuItem(value: 'info',  child: Text('Info')),
              ],
              onChanged: (v) {
                setState(() => _nivelFiltro = v ?? 'todos');
                _cargar();
              },
            )),
            const SizedBox(width: 8),
            // Buscar por UID
            Expanded(flex: 2, child: TextField(
              controller: _uidCtrl,
              style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13),
              decoration: InputDecoration(
                labelText: 'Filtrar por usuario',
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                suffixIcon: _uidCtrl.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear, size: 16),
                        onPressed: () { _uidCtrl.clear(); _cargar(); }),
              ),
              onSubmitted: (_) => _cargar(),
            )),
          ]),
        ),
        // ── Lista ─────────────────────────────────────────────────────────────
        Expanded(child: _loading
            ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
            : _error != null
                ? Center(child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.error_outline, color: AppTheme.danger, size: 48),
                      const SizedBox(height: 12),
                      Text(_error!, style: const TextStyle(color: AppTheme.danger),
                          textAlign: TextAlign.center),
                      const SizedBox(height: 16),
                      ElevatedButton(onPressed: _cargar, child: const Text('Reintentar')),
                    ]),
                  ))
                : _logs.isEmpty
                    ? const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.check_circle_outline, color: AppTheme.success, size: 48),
                        SizedBox(height: 12),
                        Text('Sin errores registrados',
                            style: TextStyle(color: AppTheme.textSecondary, fontSize: 16)),
                        SizedBox(height: 4),
                        Text('El servidor está funcionando sin problemas.',
                            style: TextStyle(color: AppTheme.textMuted, fontSize: 13)),
                      ]))
                    : ListView.separated(
                        padding: const EdgeInsets.all(12),
                        itemCount: _logs.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (_, i) => _LogTile(log: _logs[i] as Map<String, dynamic>),
                      ),
        ),
      ]),
    );
  }
}

class _LogTile extends StatefulWidget {
  final Map<String, dynamic> log;
  const _LogTile({required this.log});
  @override
  State<_LogTile> createState() => _LogTileState();
}

class _LogTileState extends State<_LogTile> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final nivel   = widget.log['nivel'] as String? ?? 'error';
    final ruta    = widget.log['ruta'] as String? ?? '?';
    final uid     = widget.log['firebase_uid'] as String? ?? '-';
    final mensaje = widget.log['mensaje'] as String? ?? '';
    final stack   = widget.log['stack'] as String?;
    final body    = widget.log['req_body'] as String?;
    final ts      = widget.log['created_at'] as String? ?? '';

    final color = nivel == 'error' ? AppTheme.danger
        : nivel == 'warn' ? AppTheme.warning
        : AppTheme.info;

    String fechaStr = '';
    try {
      final dt = DateTime.parse(ts).toLocal();
      fechaStr = DateFormat('dd/MM HH:mm:ss').format(dt);
    } catch (_) { fechaStr = ts; }

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // ── Cabecera ────────────────────────────────────────────────────────
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(nivel.toUpperCase(),
                    style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w800)),
              ),
              const SizedBox(width: 8),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(ruta, style: const TextStyle(color: AppTheme.textPrimary,
                    fontSize: 12, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(mensaje, maxLines: _expanded ? 20 : 2, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
              ])),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(fechaStr, style: const TextStyle(color: AppTheme.textMuted, fontSize: 10)),
                const SizedBox(height: 4),
                Icon(_expanded ? Icons.expand_less : Icons.expand_more,
                    color: AppTheme.textMuted, size: 16),
              ]),
            ]),
          ),
        ),
        // ── Detalle expandido ────────────────────────────────────────────────
        if (_expanded) ...[
          Divider(color: AppTheme.border, height: 1),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // UID
              if (uid != '-') ...[
                _campo('Usuario', uid),
                const SizedBox(height: 8),
              ],
              // Stack trace
              if (stack != null && stack.isNotEmpty) ...[
                _campo('Stack trace', stack, mono: true),
                const SizedBox(height: 8),
              ],
              // Body del request
              if (body != null && body.isNotEmpty) ...[
                _campo('Request body', body, mono: true),
              ],
            ]),
          ),
        ],
      ]),
    );
  }

  Widget _campo(String label, String valor, {bool mono = false}) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(color: AppTheme.textMuted,
          fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.6)),
      const SizedBox(height: 4),
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: AppTheme.background,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: AppTheme.border),
        ),
        child: SelectableText(
          valor,
          style: TextStyle(
            color: AppTheme.textSecondary,
            fontSize: mono ? 10 : 12,
            fontFamily: mono ? 'monospace' : null,
            height: 1.5,
          ),
        ),
      ),
    ]);
  }
}
