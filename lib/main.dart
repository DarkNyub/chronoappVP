import 'dart:async';
import 'package:flutter/material.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  // Asegura que los bindings de Flutter estén inicializados antes de ejecutar la app.
  WidgetsFlutterBinding.ensureInitialized();

  // Configura la aplicación en modo inmersivo (oculta barra de estado y de navegación).
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

  runApp(const MyApp());
}

/// Define los 3 modos de tiempo disponibles en la aplicación.
enum TimeType { clock, timer, stopwatch }

// --- PALETAS DE COLORES ---
// bgColors: Colores oscuros y sólidos para los fondos.
final List<Color> bgColors = [
  Colors.black,
  Colors.red[900]!,
  Colors.blue[900]!,
  Colors.green[900]!,
  Colors.orange[900]!,
  Colors.purple[900]!,
  Colors.grey[800]!,
];

// brightColors: Colores brillantes/neón optimizados para resaltar sobre los fondos oscuros.
final List<Color> brightColors = [
  Colors.white,
  Colors.cyanAccent,
  Colors.yellowAccent,
  Colors.greenAccent,
  Colors.pinkAccent,
  Colors.orangeAccent,
  Colors.redAccent,
];

/// Modelo de datos principal para cada bloque de la interfaz.
/// Utiliza [ValueNotifier] para implementar "State Isolation" y evitar redibujar
/// toda la pantalla cuando el tiempo cambia.
class TimeBlock {
  TimeType type;
  ValueNotifier<int> timeMs; // Estado reactivo del tiempo en milisegundos.
  int
  initialTimeMs; // Guarda el tiempo inicial para calcular la barra de progreso.
  bool isRunning; // Indica si el cronómetro/temporizador está activo.
  bool editMode; // Indica si el usuario está ajustando los dígitos.

  // Configuración de apariencia
  Color ltColor;
  Color bgColor;
  double fontScale;

  // Configuración de alertas (Aplica principalmente para el Temporizador)
  bool playSound;
  bool enableVibration;

  TimeBlock({
    required this.type,
    int initialMs = 0,
    this.initialTimeMs = 0,
    this.isRunning = false,
    this.editMode = false,
    this.ltColor = Colors.white,
    this.bgColor = Colors.black,
    this.fontScale = 10.0,
    this.playSound = true,
    this.enableVibration = true,
  }) : timeMs = ValueNotifier<int>(initialMs);
}

/// Muestra un modal global con las Preguntas Frecuentes (FAQ).
/// Se invoca tanto en el onboarding (primera ejecución) como desde el botón '?'.
void showFaqDialog(BuildContext context) {
  showDialog(
    context: context,
    builder: (context) {
      return AlertDialog(
        backgroundColor: Colors.black,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: Colors.white24),
        ),
        title: const Row(
          children: [
            Icon(Icons.help_outline, color: Colors.white),
            SizedBox(width: 10),
            Text(
              "¿Cómo funciona?",
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView(
            shrinkWrap: true,
            children: [
              _buildFaqItem(
                Icons.touch_app,
                "Controles Ocultos",
                "Toca la pantalla una vez para revelar los controles de Play, Pausa y Reinicio.",
              ),
              _buildFaqItem(
                Icons.history,
                "Cambiar Modo",
                "Desliza horizontalmente para cambiar entre Temporizador y Cronómetro.",
              ),
              _buildFaqItem(
                Icons.edit,
                "Ajustar Tiempo",
                "Haz doble toque para entrar en modo edición (aparecerán flechas). Doble toque para salir.",
              ),
              _buildFaqItem(
                Icons.settings,
                "Personalización",
                "Usa el engranaje para cambiar colores, tamaño y alarmas. ¡Disfruta el efecto Neón!",
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              "ENTENDIDO",
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      );
    },
  );
}

/// Helper visual para construir cada ítem dentro del FAQ.
Widget _buildFaqItem(IconData icon, String title, String description) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: Colors.white, size: 28),
        const SizedBox(width: 15),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                description,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'ChronoVP',
      home: TimeScreen(),
    );
  }
}

/// Pantalla principal que orquesta los 3 bloques de tiempo.
/// Implementa [WidgetsBindingObserver] para manejar el estado en segundo plano (Background Lifecycle).
class TimeScreen extends StatefulWidget {
  const TimeScreen({super.key});

  @override
  State<TimeScreen> createState() => _TimeScreenState();
}

class _TimeScreenState extends State<TimeScreen> with WidgetsBindingObserver {
  // Inicialización de los 3 bloques principales
  final clock = TimeBlock(type: TimeType.clock, fontScale: 6.0);
  final timer = TimeBlock(type: TimeType.timer);
  final chrono = TimeBlock(type: TimeType.stopwatch);

  DateTime? _pausedTime; // Registra el momento exacto en que la app se minimiza

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(
      this,
    ); // Comienza a escuchar el ciclo de vida
    WakelockPlus.enable(); // Previene que la pantalla se apague automáticamente

    loadPreferences();
    checkFirstRun(); // Verifica si es la primera vez que se abre la app

    // Loop principal: Se ejecuta cada segundo.
    // NOTA: No usa setState() global, por lo que es altamente eficiente.
    Timer.periodic(const Duration(seconds: 1), (_) {
      update(timer);
      update(chrono);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Maneja los cambios de estado de la aplicación (Foreground / Background).
  /// Esto asegura que el tiempo siga siendo preciso incluso si el usuario minimiza la app.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _pausedTime = DateTime.now(); // Guardar el timestamp al salir
    } else if (state == AppLifecycleState.resumed && _pausedTime != null) {
      // Calcular cuántos milisegundos pasaron en segundo plano
      final diffMs = DateTime.now().difference(_pausedTime!).inMilliseconds;

      // Aplicar la diferencia a los bloques que estaban corriendo
      if (timer.isRunning) {
        timer.timeMs.value -= diffMs;
        if (timer.timeMs.value < 0) timer.timeMs.value = 0;
      }
      if (chrono.isRunning) {
        chrono.timeMs.value += diffMs;
      }
      _pausedTime = null; // Resetear la variable
    }
  }

  /// Muestra el popup de FAQ solo la primera vez que se instala/abre la app.
  Future<void> checkFirstRun() async {
    final prefs = await SharedPreferences.getInstance();
    bool isFirstRun = prefs.getBool('isFirstRun') ?? true;
    if (isFirstRun) {
      await prefs.setBool('isFirstRun', false);
      // Espera a que termine el primer frame para poder mostrar un Dialog sin errores
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) showFaqDialog(context);
      });
    }
  }

  /// Función principal de cálculo de tiempo. Actualiza el ValueNotifier.
  void update(TimeBlock b) async {
    if (!b.isRunning) return;

    if (b.type == TimeType.timer) {
      if (b.timeMs.value > 0) {
        b.timeMs.value -= 1000;
      } else if (b.timeMs.value <= 0) {
        // El temporizador llegó a cero
        b.isRunning = false;
        b.timeMs.value = 0;
      }
    } else if (b.type == TimeType.stopwatch) {
      b.timeMs.value += 1000;
    }
  }

  // --- MÉTODOS DE PERSISTENCIA (SharedPreferences) ---

  /// Guarda toda la configuración actual en la memoria del dispositivo
  Future<void> savePreferences() async {
    final prefs = await SharedPreferences.getInstance();
    final blocks = {'clock': clock, 'timer': timer, 'chrono': chrono};

    blocks.forEach((key, b) async {
      await prefs.setInt("${key}Color", b.ltColor.value);
      await prefs.setInt("${key}BgColor", b.bgColor.value);
      await prefs.setDouble("${key}Scale", b.fontScale);
    });

    // Guardar ajustes específicos del temporizador
    await prefs.setBool("timerSound", timer.playSound);
    await prefs.setBool("timerVib", timer.enableVibration);
  }

  /// Carga la configuración al iniciar la app
  Future<void> loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _loadBlockPrefs(prefs, 'clock', clock, defaultScale: 6.0);
      _loadBlockPrefs(prefs, 'timer', timer, defaultScale: 10.0);
      _loadBlockPrefs(prefs, 'chrono', chrono, defaultScale: 10.0);

      timer.playSound = prefs.getBool("timerSound") ?? true;
      timer.enableVibration = prefs.getBool("timerVib") ?? true;
    });
  }

  /// Helper para cargar las propiedades repetitivas de cada bloque
  void _loadBlockPrefs(
    SharedPreferences prefs,
    String key,
    TimeBlock b, {
    required double defaultScale,
  }) {
    b.ltColor = Color(prefs.getInt("${key}Color") ?? Colors.white.value);
    b.bgColor = Color(prefs.getInt("${key}BgColor") ?? Colors.black.value);
    b.fontScale = prefs.getDouble("${key}Scale") ?? defaultScale;
  }

  // --- CONSTRUCCIÓN DE LA UI PRINCIPAL (Responsive) ---
  @override
  Widget build(BuildContext context) {
    final isVertical =
        MediaQuery.of(context).orientation == Orientation.portrait;
    return Scaffold(
      backgroundColor: Colors.black,
      body: isVertical ? buildVertical() : buildHorizontal(),
    );
  }

  Widget buildVertical() {
    return Column(
      children: [
        Expanded(
          child: TimeWidget(block: clock, onSettingsChanged: savePreferences),
        ),
        Expanded(
          child: TimeWidget(block: chrono, onSettingsChanged: savePreferences),
        ),
        Expanded(
          child: TimeWidget(block: timer, onSettingsChanged: savePreferences),
        ),
      ],
    );
  }

  Widget buildHorizontal() {
    return Row(
      children: [
        Expanded(
          child: Column(
            children: [
              Expanded(
                child: TimeWidget(
                  block: clock,
                  onSettingsChanged: savePreferences,
                ),
              ),
              Expanded(
                child: TimeWidget(
                  block: timer,
                  onSettingsChanged: savePreferences,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: TimeWidget(block: chrono, onSettingsChanged: savePreferences),
        ),
      ],
    );
  }
}

/// Widget individual que renderiza un bloque de tiempo (Reloj, Timer o Chrono).
class TimeWidget extends StatefulWidget {
  final TimeBlock block;
  final Function
  onSettingsChanged; // Callback para disparar el guardado de preferencias

  const TimeWidget({
    super.key,
    required this.block,
    required this.onSettingsChanged,
  });

  @override
  State<TimeWidget> createState() => _TimeWidgetState();
}

class _TimeWidgetState extends State<TimeWidget> {
  // Controles flotantes ocultos
  bool _showControls = false;
  Timer? _controlsTimer;

  /// Muestra los controles flotantes y programa su ocultamiento automático tras 3 segundos.
  void showControls() {
    if (widget.block.type == TimeType.clock)
      return; // El reloj no tiene controles
    setState(() => _showControls = true);

    _controlsTimer?.cancel();
    _controlsTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _showControls = false);
    });
  }

  // --- LÓGICA DE MANIPULACIÓN DE TIEMPO ---

  /// Convierte milisegundos en una lista de 6 dígitos: [H, H, M, M, S, S]
  List<int> splitTime(int ms) {
    int total = ms ~/ 1000;
    int h = total ~/ 3600;
    int m = (total % 3600) ~/ 60;
    int s = total % 60;
    return [h ~/ 10, h % 10, m ~/ 10, m % 10, s ~/ 10, s % 10];
  }

  /// Une una lista de 6 dígitos convirtiéndolos de nuevo en milisegundos
  int joinTime(List<int> d) {
    int h = d[0] * 10 + d[1];
    int m = d[2] * 10 + d[3];
    int s = d[4] * 10 + d[5];
    return ((h * 3600) + (m * 60) + s) * 1000;
  }

  /// Cambia un dígito individual (arriba/abajo) respetando los límites de base 60.
  void changeDigit(int index, int delta) {
    if (widget.block.isRunning) return;
    var digits = splitTime(widget.block.timeMs.value);
    digits[index] += delta;

    // Límite para decenas de minutos y decenas de segundos (max 5)
    var maxLimit = (index == 2 || index == 4) ? 5 : 9;

    // Comportamiento cíclico
    if (digits[index] < 0) digits[index] = maxLimit;
    if (digits[index] > maxLimit) digits[index] = 0;

    int newTime = joinTime(digits);
    widget.block.timeMs.value = newTime;
    widget.block.initialTimeMs =
        newTime; // Setea base para la barra de progreso
  }

  // --- INTERACCIONES DEL USUARIO ---

  /// Cambia el tipo de bloque entre Temporizador y Cronómetro al deslizar
  void toggleType() {
    if (widget.block.type == TimeType.clock) return;
    setState(() {
      widget.block.type = widget.block.type == TimeType.timer
          ? TimeType.stopwatch
          : TimeType.timer;
      widget.block.timeMs.value = 0;
      widget.block.initialTimeMs = 0;
      widget.block.isRunning = false;
      widget.block.editMode = false;
    });
  }

  /// Inicia o pausa el flujo de tiempo
  void toggleRun() {
    if (widget.block.type == TimeType.clock || widget.block.editMode) return;

    // Si inicia un timer, congela su valor inicial para calcular la barra de progreso
    if (!widget.block.isRunning &&
        widget.block.type == TimeType.timer &&
        widget.block.initialTimeMs == 0) {
      widget.block.initialTimeMs = widget.block.timeMs.value;
    }

    setState(() {
      widget.block.isRunning = !widget.block.isRunning;
    });
    showControls();
  }

  /// Detiene y reinicia el tiempo (a cero para chrono, al inicial para timer)
  void resetTime() {
    setState(() {
      widget.block.isRunning = false;
      widget.block.timeMs.value = widget.block.type == TimeType.timer
          ? widget.block.initialTimeMs
          : 0;
    });
  }

  /// Obtiene la hora actual del sistema en formato string "HH:MM"
  String getClock() {
    final now = DateTime.now();
    return "${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}";
  }

  String getLabel() {
    switch (widget.block.type) {
      case TimeType.clock:
        return "HORA ACTUAL";
      case TimeType.timer:
        return "TEMPORIZADOR";
      case TimeType.stopwatch:
        return "CRONÓMETRO";
    }
  }

  // --- MENÚS Y DIÁLOGOS ---

  /// Muestra el modal inferior de configuración visual y funcional
  void showSettingsDialog() {
    showDialog(
      context: context,
      builder: (context) {
        // StatefulBuilder permite que el modal se redibuje a sí mismo en tiempo real
        return StatefulBuilder(
          builder: (context, setModalState) {
            return AlertDialog(
              backgroundColor: Colors.grey[900],
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              title: const Text(
                "Configuración",
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // SLIDER DE TAMAÑO
                    Text(
                      "Tamaño: ${widget.block.fontScale.toInt()}",
                      style: const TextStyle(color: Colors.white70),
                    ),
                    Slider(
                      value: widget.block.fontScale,
                      min: 1.0,
                      max: 10.0,
                      divisions: 9,
                      activeColor: widget.block.ltColor,
                      onChanged: (val) {
                        setModalState(() => widget.block.fontScale = val);
                        setState(() {}); // Actualiza la UI subyacente
                        widget.onSettingsChanged();
                      },
                    ),
                    const Divider(color: Colors.white24, height: 30),

                    // PALETA DE COLORES NEÓN (TEXTO)
                    const Text(
                      "Color Neón (Dígitos)",
                      style: TextStyle(color: Colors.white70),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: brightColors.map((c) {
                        return GestureDetector(
                          onTap: () {
                            setModalState(() => widget.block.ltColor = c);
                            setState(() {});
                            widget.onSettingsChanged();
                          },
                          child: Container(
                            width: 45,
                            height: 45,
                            decoration: BoxDecoration(
                              color: c,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: widget.block.ltColor == c
                                    ? Colors.white
                                    : Colors.transparent,
                                width: 3,
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const Divider(color: Colors.white24, height: 30),

                    // PALETA DE COLORES BASE (FONDO)
                    const Text(
                      "Color de Fondo",
                      style: TextStyle(color: Colors.white70),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: bgColors.map((c) {
                        return GestureDetector(
                          onTap: () {
                            setModalState(() => widget.block.bgColor = c);
                            setState(() {});
                            widget.onSettingsChanged();
                          },
                          child: Container(
                            width: 45,
                            height: 45,
                            decoration: BoxDecoration(
                              color: c,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: widget.block.bgColor == c
                                    ? Colors.white
                                    : Colors.white24,
                                width: widget.block.bgColor == c ? 3 : 1,
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),

                    // RENDERIZADO CONDICIONAL: Ajustes de alarma exclusivos del Timer
                    if (widget.block.type == TimeType.timer) ...[
                      const Divider(color: Colors.white24, height: 30),
                      const Text(
                        "Alertas de finalización",
                        style: TextStyle(color: Colors.white70),
                      ),
                      const SizedBox(height: 10),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text(
                          "Sonido",
                          style: TextStyle(color: Colors.white, fontSize: 15),
                        ),
                        activeColor: widget.block.ltColor,
                        value: widget.block.playSound,
                        onChanged: (val) {
                          setModalState(() => widget.block.playSound = val);
                          widget.onSettingsChanged();
                        },
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text(
                          "Vibración",
                          style: TextStyle(color: Colors.white, fontSize: 15),
                        ),
                        activeColor: widget.block.ltColor,
                        value: widget.block.enableVibration,
                        onChanged: (val) {
                          setModalState(
                            () => widget.block.enableVibration = val,
                          );
                          widget.onSettingsChanged();
                        },
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text(
                    "CERRAR",
                    style: TextStyle(color: Colors.white, fontSize: 16),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // --- WIDGETS DE CONSTRUCCIÓN VISUAL ---

  /// Construye las flechas de ajuste. Usa HitTestBehavior.opaque para
  /// que todo el espacio vacío cuente como área táctil (Mejora de UX).
  Widget buildArrow(int index, int delta, IconData icon) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => changeDigit(index, delta),
      child: SizedBox(
        height: 120,
        width: 150,
        child: FittedBox(
          child: Icon(icon, color: widget.block.ltColor.withOpacity(0.8)),
        ),
      ),
    );
  }

  /// Construye cada dígito de la interfaz junto con sus flechas si está en editMode.
  /// Contiene el estilo "Neón" usando propiedades de Shadow.
  Widget buildDigit(int i, List<int> digits) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.block.editMode) buildArrow(i, 1, Icons.arrow_drop_up),
        Text(
          digits[i].toString(),
          style: TextStyle(
            fontFamily: 'Digital', // Dependencia: Fuente instalada localmente
            color: widget.block.ltColor,
            fontSize: 300,
            fontWeight: FontWeight.bold,
            height: 0.9,
            shadows: [
              Shadow(
                color: widget.block.ltColor,
                blurRadius: 25.0,
              ), // Glow exterior
              const Shadow(
                color: Colors.white54,
                blurRadius: 5.0,
              ), // Núcleo brillante
            ],
          ),
        ),
        if (widget.block.editMode) buildArrow(i, -1, Icons.arrow_drop_down),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      // Gestos principales del bloque
      onHorizontalDragEnd: (details) {
        if (details.primaryVelocity != null &&
            details.primaryVelocity!.abs() > 300)
          toggleType();
      },
      onDoubleTap: () {
        if (widget.block.type == TimeType.clock) return;
        setState(() => widget.block.editMode = !widget.block.editMode);
      },
      onTap: showControls, // Toque simple revela los botones flotantes

      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        color: widget.block.bgColor,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // --- CAPA INFERIOR: TEXTOS Y BARRAS ---
            Column(
              children: [
                Expanded(
                  child: Center(
                    child: FractionallySizedBox(
                      widthFactor: widget.block.fontScale / 10,
                      heightFactor: widget.block.fontScale / 10,
                      child: widget.block.type == TimeType.clock
                          // CASO 1: RELOJ ACTUAL (Actualizado por el Timer principal)
                          ? FittedBox(
                              fit: BoxFit.contain,
                              child: Text(
                                getClock(),
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontFamily: 'Digital',
                                  color: widget.block.ltColor,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 5,
                                  shadows: [
                                    Shadow(
                                      color: widget.block.ltColor,
                                      blurRadius: 20,
                                    ),
                                  ],
                                ),
                              ),
                            )
                          // CASO 2: TIMER O CHRONO (Aislados reactivamente con ValueListenableBuilder)
                          : ValueListenableBuilder<int>(
                              valueListenable: widget.block.timeMs,
                              builder: (context, timeValue, child) {
                                final digits = splitTime(timeValue);
                                return FittedBox(
                                  fit: BoxFit.contain,
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: List.generate(6, (i) {
                                      return Row(
                                        children: [
                                          buildDigit(i, digits),
                                          // Separadores ":"
                                          if (i == 1 || i == 3)
                                            Text(
                                              ":",
                                              style: TextStyle(
                                                fontFamily: 'Digital',
                                                color: widget.block.ltColor,
                                                fontSize: 300,
                                                fontWeight: FontWeight.bold,
                                                height: 0.9,
                                                shadows: [
                                                  Shadow(
                                                    color: widget.block.ltColor,
                                                    blurRadius: 20,
                                                  ),
                                                ],
                                              ),
                                            ),
                                        ],
                                      );
                                    }),
                                  ),
                                );
                              },
                            ),
                    ),
                  ),
                ),

                // Barra de progreso visual (Solo activa en el Temporizador en curso)
                if (widget.block.type == TimeType.timer &&
                    widget.block.initialTimeMs > 0)
                  ValueListenableBuilder<int>(
                    valueListenable: widget.block.timeMs,
                    builder: (context, timeValue, child) {
                      double progress = timeValue / widget.block.initialTimeMs;
                      return LinearProgressIndicator(
                        value: progress,
                        minHeight: 3,
                        backgroundColor: Colors.transparent,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          widget.block.ltColor.withOpacity(0.5),
                        ),
                      );
                    },
                  ),

                // Etiqueta del bloque (Ej: "CRONÓMETRO")
                Padding(
                  padding: const EdgeInsets.only(bottom: 10, top: 5),
                  child: Text(
                    getLabel(),
                    style: TextStyle(
                      color: widget.block.ltColor.withOpacity(0.6),
                      fontSize: 14,
                      letterSpacing: 2,
                    ),
                  ),
                ),
              ],
            ),

            // --- CAPA MEDIA: CONTROLES FLOTANTES ---
            if (widget.block.type != TimeType.clock && !widget.block.editMode)
              AnimatedOpacity(
                opacity: _showControls ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 300),
                child: IgnorePointer(
                  ignoring:
                      !_showControls, // Evita toques fantasma cuando están invisibles
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.7),
                      borderRadius: BorderRadius.circular(30),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          iconSize: 40,
                          color: Colors.white,
                          icon: Icon(
                            widget.block.isRunning
                                ? Icons.pause_circle_filled
                                : Icons.play_circle_fill,
                          ),
                          onPressed: toggleRun,
                        ),
                        const SizedBox(width: 20),
                        IconButton(
                          iconSize: 40,
                          color: Colors.white,
                          icon: const Icon(Icons.refresh),
                          onPressed: resetTime,
                        ),
                      ],
                    ),
                  ),
                ),
              ),

            // --- CAPA SUPERIOR: ICONOS DE ESQUINA ---
            // Icono Settings (Arriba a la izquierda)
            Positioned(
              top: 10,
              left: 10,
              child: GestureDetector(
                onTap: showSettingsDialog,
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.black45,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Icon(
                    Icons.settings,
                    color: Colors.white,
                    size: 16,
                  ),
                ),
              ),
            ),

            // Icono FAQ (Arriba a la derecha - Condicionado solo al Reloj Actual)
            if (widget.block.type == TimeType.clock)
              Positioned(
                top: 10,
                right: 10,
                child: GestureDetector(
                  onTap: () => showFaqDialog(context),
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.black45,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Icon(
                      Icons.help_outline,
                      color: Colors.white,
                      size: 16,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
