import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../theme/app_theme.dart';
import '../services/ia_service.dart';
import 'ia_diagnostico_sheet.dart';
import 'ia_reporte_sheet.dart';

class IaChatScreen extends StatefulWidget {
  final String firebaseUid;
  final int? presupuestoId;

  const IaChatScreen({
    super.key,
    required this.firebaseUid,
    this.presupuestoId,
  });

  @override
  State<IaChatScreen> createState() => _IaChatScreenState();
}

class _IaChatScreenState extends State<IaChatScreen> {
  final _ctrl   = TextEditingController();
  final _scroll = ScrollController();
  final List<_Msg> _msgs = [];
  bool _enviando = false;

  static const _sugerencias = [
    '¿En qué se me fue más dinero este mes?',
    '¿Cómo van mis deudas?',
    '¿Cuánto me queda disponible?',
    'Dame un resumen de mis finanzas',
  ];

  List<Map<String, dynamic>> get _historial => _msgs
      .map((m) => {'role': m.esUsuario ? 'user' : 'assistant', 'content': m.texto})
      .toList();

  Future<void> _enviar(String texto) async {
    final msg = texto.trim();
    if (msg.isEmpty || _enviando) return;
    _ctrl.clear();
    setState(() {
      _msgs.add(_Msg(texto: msg, esUsuario: true));
      _enviando = true;
    });
    _scrollAbajo();

    try {
      final histPrevio = _historial.length > 1
          ? _historial.sublist(0, _historial.length - 1)
          : <Map<String, dynamic>>[];
      final r = await IaService.chat(
        widget.firebaseUid,
        msg,
        presupuestoId: widget.presupuestoId,
        historial: histPrevio,
      );
      if (mounted) {
        setState(() {
          _msgs.add(_Msg(texto: r['respuesta'] as String? ?? '…', esUsuario: false));
          _enviando = false;
        });
        _scrollAbajo();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _msgs.add(_Msg(
            texto: 'No pude conectarme. Revisa tu conexión e intenta de nuevo.',
            esUsuario: false,
            esError: true,
          ));
          _enviando = false;
        });
      }
    }
  }

  void _scrollAbajo() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.surface,
        title: Row(children: [
          const Icon(Icons.auto_awesome, color: AppTheme.primary, size: 18),
          const SizedBox(width: 8),
          Text('Asesor IA',
              style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w700)),
        ]),
        iconTheme: IconThemeData(color: AppTheme.textPrimary),
        actions: [
          IconButton(
            icon: Icon(Icons.search_outlined, color: AppTheme.textSecondary, size: 22),
            tooltip: 'Diagnóstico',
            onPressed: () => IaDiagnosticoSheet.show(context, widget.firebaseUid),
          ),
          IconButton(
            icon: Icon(Icons.summarize_outlined, color: AppTheme.textSecondary, size: 22),
            tooltip: 'Reporte del período',
            onPressed: () => IaReporteSheet.show(context, widget.firebaseUid),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(height: 1, color: AppTheme.border),
        ),
      ),
      body: Column(children: [
        Expanded(
          child: _msgs.isEmpty
              ? _buildBienvenida()
              : ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  itemCount: _msgs.length + (_enviando ? 1 : 0),
                  itemBuilder: (_, i) {
                    if (i == _msgs.length) return _buildTyping();
                    return _buildBurbuja(_msgs[i]);
                  },
                ),
        ),
        _buildInput(context),
      ]),
    );
  }

  Widget _buildBienvenida() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(children: [
        const SizedBox(height: 12),
        Container(
          width: 64, height: 64,
          decoration: BoxDecoration(
            color: AppTheme.primary.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.auto_awesome, color: AppTheme.primary, size: 30),
        ),
        const SizedBox(height: 16),
        Text('Hola, soy tu asesor financiero',
            style: TextStyle(color: AppTheme.textPrimary, fontSize: 17, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Text(
          'Pregúntame sobre tus gastos, deudas o en qué puedes mejorar.\nConsulto tus datos reales antes de responder.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppTheme.textSecondary, fontSize: 13, height: 1.5),
        ),
        const SizedBox(height: 24),
        ...(_sugerencias.map(_buildChipSugerencia)),
        const SizedBox(height: 12),
        Divider(color: AppTheme.border),
        const SizedBox(height: 12),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          _buildAccionRapida(
            Icons.search_outlined,
            'Diagnóstico',
            () => IaDiagnosticoSheet.show(context, widget.firebaseUid),
          ),
          const SizedBox(width: 12),
          _buildAccionRapida(
            Icons.summarize_outlined,
            'Reporte',
            () => IaReporteSheet.show(context, widget.firebaseUid),
          ),
        ]),
      ]),
    );
  }

  Widget _buildChipSugerencia(String texto) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GestureDetector(
        onTap: () => _enviar(texto),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppTheme.border),
          ),
          child: Row(children: [
            const Icon(Icons.chevron_right, color: AppTheme.primary, size: 18),
            const SizedBox(width: 10),
            Expanded(child: Text(texto,
                style: TextStyle(color: AppTheme.textPrimary, fontSize: 14))),
          ]),
        ),
      ),
    );
  }

  Widget _buildAccionRapida(IconData icon, String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppTheme.primary.withValues(alpha: 0.4)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: AppTheme.primary, size: 15),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(color: AppTheme.primary, fontSize: 13, fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }

  Widget _buildBurbuja(_Msg m) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: m.esUsuario ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!m.esUsuario) ...[
            CircleAvatar(
              radius: 14,
              backgroundColor: AppTheme.primary.withValues(alpha: 0.12),
              child: const Icon(Icons.auto_awesome, color: AppTheme.primary, size: 14),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: m.esUsuario
                    ? AppTheme.primary.withValues(alpha: 0.15)
                    : m.esError
                        ? AppTheme.danger.withValues(alpha: 0.08)
                        : AppTheme.surface,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(m.esUsuario ? 16 : 4),
                  bottomRight: Radius.circular(m.esUsuario ? 4 : 16),
                ),
                border: m.esUsuario ? null : Border.all(color: AppTheme.border),
              ),
              child: m.esUsuario || m.esError
              ? Text(
                  m.texto,
                  style: TextStyle(
                    color: m.esError ? AppTheme.danger : AppTheme.textPrimary,
                    fontSize: 14, height: 1.6,
                  ),
                )
              : MarkdownBody(
                  data: m.texto,
                  styleSheet: MarkdownStyleSheet(
                    p: TextStyle(color: AppTheme.textPrimary, fontSize: 14, height: 1.6),
                    strong: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w700, fontSize: 14),
                    h2: TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w700, fontSize: 14),
                    h3: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600, fontSize: 14),
                    listBullet: TextStyle(color: AppTheme.textSecondary, fontSize: 14),
                    blockquoteDecoration: BoxDecoration(
                      color: AppTheme.surfaceAlt,
                      borderRadius: BorderRadius.circular(4),
                      border: Border(left: BorderSide(color: AppTheme.primary, width: 3)),
                    ),
                  ),
                  shrinkWrap: true,
                ),
            ),
          ),
          if (m.esUsuario) const SizedBox(width: 8),
        ],
      ),
    );
  }

  Widget _buildTyping() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        CircleAvatar(
          radius: 14,
          backgroundColor: AppTheme.primary.withValues(alpha: 0.12),
          child: const Icon(Icons.auto_awesome, color: AppTheme.primary, size: 14),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(16), topRight: Radius.circular(16),
              bottomLeft: Radius.circular(4), bottomRight: Radius.circular(16),
            ),
            border: Border.all(color: AppTheme.border),
          ),
          child: SizedBox(
            width: 36, height: 6,
            child: LinearProgressIndicator(
              color: AppTheme.primary,
              backgroundColor: AppTheme.border,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _buildInput(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(12, 8, 12, 12 + MediaQuery.of(context).viewInsets.bottom),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        border: Border(top: BorderSide(color: AppTheme.border)),
      ),
      child: Row(children: [
        Expanded(
          child: TextField(
            controller: _ctrl,
            style: TextStyle(color: AppTheme.textPrimary, fontSize: 14),
            decoration: InputDecoration(
              hintText: 'Pregúntame algo…',
              hintStyle: TextStyle(color: AppTheme.textMuted, fontSize: 14),
              filled: true,
              fillColor: AppTheme.surfaceAlt,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(22),
                borderSide: BorderSide.none,
              ),
            ),
            textInputAction: TextInputAction.send,
            onSubmitted: _enviar,
            minLines: 1,
            maxLines: 4,
          ),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: _enviando ? null : () => _enviar(_ctrl.text),
          child: Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              color: _enviando ? AppTheme.border : AppTheme.primary,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.send_rounded,
              color: _enviando ? AppTheme.textMuted : Colors.black,
              size: 18,
            ),
          ),
        ),
      ]),
    );
  }
}

class _Msg {
  final String texto;
  final bool esUsuario;
  final bool esError;
  const _Msg({required this.texto, required this.esUsuario, this.esError = false});
}
