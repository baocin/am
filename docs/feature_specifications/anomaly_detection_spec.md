# Multi-Stream Anomaly Detection System
## Technical Specification v1.0

---

## 1. System Overview

### 1.1 Purpose
Design and implement a robust real-time anomaly detection system for 30+ heterogeneous time series streams (GPS, accelerometer, speech activity, app events, etc.) with built-in handling for missing data, gaps, and varying data frequencies.

### 1.2 Key Requirements
- **Multi-modal support**: Handle arbitrary data types (audio, sensor, behavioral)
- **Missing data resilience**: Graceful degradation with sensor outages
- **Real-time processing**: Sub-second response times for streaming data
- **Gap pattern learning**: Distinguish normal vs anomalous data availability patterns
- **Causal explanation**: Understand WHY anomalies occur, not just detect them
- **Scalable architecture**: Support 30+ streams with room for growth

### 1.3 Architecture Overview
```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Tier 1        │    │     Tier 2       │    │    Tier 3       │    │    Tier 4       │
│ Individual      │    │ Cross-Stream     │    │   Ensemble      │    │   Causal        │
│ River Models    │───▶│ River Detection  │───▶│   & Meta-       │───▶│   Explanation   │
│ (30+ models)    │    │ (Gap-Aware)      │    │   Learning      │    │   Layer         │
└─────────────────┘    └──────────────────┘    └─────────────────┘    └─────────────────┘
```

---

## 2. Core Components

### 2.1 Tier 1: Individual Stream Analysis (River)

**Purpose**: Detect temporal anomalies within individual time series using River's streaming models for immediate learning and adaptation.

**Implementation**:
```python
class IndividualStreamAnalyzer:
    def __init__(self):
        self.river_models = {i: self._create_river_detector(i) for i in range(30)}
        self.stream_health = {i: StreamHealthTracker() for i in range(30)}
        
    def _create_river_detector(self, stream_id):
        """Choose River model based on stream characteristics"""
        stream_type = self.get_stream_type(stream_id)
        
        if stream_type == 'continuous_smooth':
            # For step counter, heart rate, etc.
            return SNARIMAX(p=1, d=1, q=1)  # ARIMA with differencing
            
        elif stream_type == 'continuous_noisy':
            # For accelerometer, audio levels, etc.
            return HoltWinters(alpha=0.3, beta=0.1, seasonal=None)
            
        elif stream_type == 'discrete_events':
            # For app launches, notifications, etc.
            return QuantileFilter(q=0.95, window_size=50)
            
        else:
            # Default: adaptive to data patterns
            return SNARIMAX()  # Auto-tuning version
    
    def analyze_stream(self, stream_id, timestamp, value):
        """Analyze individual stream for anomalies"""
        detector = self.river_models[stream_id]
        health = self.stream_health[stream_id]
        
        if not health.can_predict():
            return np.nan  # Stream unhealthy
            
        # Get prediction and calculate anomaly score
        prediction = detector.predict_one()
        anomaly_score = self._calculate_anomaly_score(value, prediction)
        
        # Learn from new value
        detector.learn_one(value)
        health.record_data_point(timestamp, value)
        
        return anomaly_score
```

**Key Features**:
- **Immediate learning**: Works from first data point, no training period required
- **Adaptive models**: Different River models for different data characteristics  
- **Continuous updates**: Real-time learning without batch retraining
- **Stream health tracking**: Monitor reliability and adjust confidence

### 2.2 Tier 2: Cross-Stream Pattern Detection (River)

**Purpose**: Detect multivariate anomalies and learn gap patterns across all streams using streaming machine learning.

**Implementation**:
```python
class CrossStreamDetector:
    def __init__(self):
        # Main multivariate detector
        self.multivariate_detector = HalfSpaceTrees(n_trees=50, height=8)
        
        # Hierarchical detectors for different sensor groups
        self.group_detectors = {
            'motion': HalfSpaceTrees(n_trees=30),     # accelerometer, step counter
            'location': HalfSpaceTrees(n_trees=30),   # GPS coordinates  
            'interaction': HalfSpaceTrees(n_trees=30), # speech, apps, screen
        }
        
    def create_features(self, timestamp, raw_data):
        features = {}
        
        # Time context
        dt = pd.to_datetime(timestamp)
        features.update({
            'hour': dt.hour,
            'day_of_week': dt.dayofweek,
            'is_weekend': dt.dayofweek >= 5,
            'is_work_hours': 9 <= dt.hour <= 17,
        })
        
        # Gap indicators (CORE INNOVATION)
        for i, stream in enumerate(self.stream_names):
            is_available = stream in raw_data and not np.isnan(raw_data[stream])
            features[f"{stream}_available"] = 1.0 if is_available else 0.0
            
            # Include actual values only when available
            if is_available:
                features[stream] = raw_data[stream]
        
        # Sensor group availability patterns
        features.update(self._compute_group_patterns(raw_data))
        
        return features
```

**Gap Pattern Learning**:
- **Availability indicators**: Boolean features for each stream's data presence
- **Group patterns**: Learn coordinated sensor failures vs individual issues
- **Context awareness**: Different gap patterns for work/sleep/weekend hours
- **Behavioral anomalies**: Detect unusual absence patterns (e.g., no phone usage during work hours)

### 2.3 Tier 3: Ensemble & Meta-Learning

**Purpose**: Combine individual and cross-stream signals with confidence weighting based on data availability.

**Implementation Options**:

**Option A: Health-Aware Weighted Ensemble**
```python
class HealthAwareEnsemble:
    def predict(self, prophet_scores, river_score, stream_health):
        # Weight Prophet scores by stream health
        health_weights = np.array([
            stream_health[i].get_health_score() for i in range(30)
        ])
        
        # Combine available scores
        available_mask = ~np.isnan(prophet_scores)
        if available_mask.sum() == 0:
            return {'score': river_score, 'confidence': 0.3}
            
        weighted_prophet = np.average(
            prophet_scores[available_mask], 
            weights=health_weights[available_mask]
        )
        
        # Final ensemble
        final_score = 0.6 * weighted_prophet + 0.4 * river_score
        confidence = available_mask.sum() / 30  # Fraction of streams available
        
        return {'score': final_score, 'confidence': confidence}

### 2.4 Tier 4: Causal Explanation Layer

**Purpose**: Explain WHY anomalies occur by analyzing causal relationships and temporal sequences between streams.

**Implementation**:
```python
class CausalExplanationLayer:
    def __init__(self):
        # Bayesian causal network
        self.causal_network = BayesianNetwork()
        self._build_causal_structure()
        
        # Event sequence analyzer
        self.sequence_analyzer = EventSequenceAnalyzer()
        
        # Temporal correlation analyzer
        self.temporal_analyzer = TemporalCausalityDetector()
        
        # Explanation thresholds
        self.explanation_threshold = 0.5
        
    def _build_causal_structure(self):
        """Define causal relationships between streams"""
        # Based on domain knowledge of sensor relationships
        causal_edges = [
            ('accelerometer_activity', 'heart_rate'),
            ('gps_movement', 'heart_rate'), 
            ('accelerometer_activity', 'gps_movement'),
            ('app_usage', 'screen_on_events'),
            ('time_of_day', 'activity_level'),
            ('ambient_light', 'screen_brightness'),
            # ... define based on your sensor ecosystem
        ]
        self.causal_network.add_edges_from(causal_edges)
    
    def should_explain(self, tier_1_results, tier_2_result, tier_3_result):
        """Determine when to run causal explanation"""
        # High final anomaly score
        if tier_3_result['score'] > 0.7:
            return True
            
        # High individual stream anomaly (even if multivariate normal)
        if max(tier_1_results.values()) > 0.8:
            return True
            
        # Conflicting signals (individual high, multivariate low)
        individual_max = max(tier_1_results.values())
        if individual_max > 0.7 and tier_2_result < 0.3:
            return True  # Needs explanation
            
        return False
    
    def explain_anomaly(self, anomaly_result, raw_data, timestamp):
        """Generate causal explanation for detected anomaly"""
        
        # Method 1: Bayesian causal inference
        causal_attribution = self._analyze_causal_network(raw_data, timestamp)
        
        # Method 2: Event sequence matching
        sequence_explanation = self._analyze_event_sequence(raw_data, timestamp)
        
        # Method 3: Temporal correlation analysis
        temporal_relationships = self._analyze_temporal_patterns(raw_data, timestamp)
        
        # Synthesize explanations
        explanation = self._synthesize_explanations(
            causal_attribution, sequence_explanation, temporal_relationships
        )
        
        return explanation
    
    def _analyze_causal_network(self, raw_data, timestamp):
        """Use Bayesian network to determine causal contributions"""
        # Fit network to recent historical data
        historical_data = self._get_historical_context(timestamp, window_hours=24)
        self.causal_network.fit_node_states_and_cpds(historical_data)
        
        # Calculate causal effects
        causal_effects = {}
        for stream, value in raw_data.items():
            if stream in self.causal_network.nodes:
                effect = self._calculate_causal_effect(stream, value)
                causal_effects[stream] = effect
                
        return causal_effects
    
    def _analyze_event_sequence(self, raw_data, timestamp):
        """Match current event sequence to learned patterns"""
        recent_events = self._get_recent_event_sequence(timestamp, window_minutes=15)
        
        # Known sequence patterns
        exercise_pattern = ['low_accel', 'accel_increase', 'gps_movement', 'heart_rate_spike']
        stress_pattern = ['normal_activity', 'heart_rate_spike', 'no_movement_change']
        medical_pattern = ['normal_state', 'sudden_anomaly', 'multiple_streams_affected']
        
        best_match = self.sequence_analyzer.find_best_match(
            recent_events, [exercise_pattern, stress_pattern, medical_pattern]
        )
        
        return {
            'sequence_type': best_match['pattern_name'],
            'confidence': best_match['similarity_score'],
            'evidence': best_match['matching_events']
        }

class EventSequenceAnalyzer:
    def __init__(self):
        self.learned_patterns = {}
        
    def find_best_match(self, current_sequence, pattern_templates):
        """Find which template pattern best matches current events"""
        best_score = 0
        best_match = None
        
        for pattern in pattern_templates:
            similarity = self._calculate_sequence_similarity(current_sequence, pattern)
            if similarity > best_score:
                best_score = similarity
                best_match = {
                    'pattern_name': pattern['name'],
                    'similarity_score': similarity,
                    'matching_events': self._get_matching_events(current_sequence, pattern)
                }
        
        return best_match

class TemporalCausalityDetector:
    def analyze_lead_lag_relationships(self, stream_a, stream_b, max_lag_minutes=10):
        """Detect temporal causality between streams"""
        correlations = {}
        
        for lag in range(-max_lag_minutes, max_lag_minutes + 1):
            if lag == 0:
                corr = np.corrcoef(stream_a, stream_b)[0, 1]
            elif lag > 0:
                # A leads B by 'lag' minutes
                corr = np.corrcoef(stream_a[:-lag], stream_b[lag:])[0, 1]
            else:
                # B leads A by 'lag' minutes
                corr = np.corrcoef(stream_a[-lag:], stream_b[:lag])[0, 1]
            
            correlations[lag] = corr
        
        # Find strongest correlation and timing
        max_lag = max(correlations, key=correlations.get)
        max_corr = correlations[max_lag]
        
        return {
            'lead_lag_minutes': max_lag,
            'correlation_strength': max_corr,
            'relationship_type': self._interpret_relationship(max_lag, max_corr)
        }
```

**Causal Explanation Output Example**:
```python
explanation = {
    'primary_cause': 'exercise_onset',
    'confidence': 0.92,
    'causal_attribution': {
        'accelerometer_contribution': 0.6,    # 60% of heart rate increase
        'gps_movement_contribution': 0.3,     # 30% of heart rate increase
        'unexplained_variance': 0.1           # 10% unknown factors
    },
    'temporal_sequence': [
        '10:31 - accelerometer activity increased',
        '10:32 - GPS detected movement start',
        '10:33 - heart rate began climbing',
        '10:35 - heart rate reached peak (150 BPM)'
    ],
    'evidence': {
        'sequence_match': 'exercise_pattern',
        'accelerometer_leads_heart_rate': '2 minutes',
        'gps_concurrent_with_heart_rate': True
    },
    'alternative_explanations': [
        {'cause': 'stress_response', 'probability': 0.05},
        {'cause': 'medical_event', 'probability': 0.03}
    ],
    'recommended_action': 'monitor_for_exercise_completion'
}
```

**Option B: Time Series Meta-Learning**
```python
class TimeSeriesMetaLearner:
    def __init__(self):
        # Treat 31 anomaly scores as multivariate time series
        self.meta_classifier = TimeSeriesForestClassifier()
        
    def fit(self, historical_anomaly_scores, labels):
        # Learn patterns in combinations of anomaly scores
        self.meta_classifier.fit(historical_anomaly_scores, labels)
```

---

## 3. Missing Data Handling Strategy

### 3.1 Data Gap Classification
```python
class GapClassifier:
    GAP_TYPES = {
        'point_missing': timedelta(minutes=5),      # Single timestamp
        'short_gap': timedelta(hours=4),            # Brief outage
        'medium_gap': timedelta(days=1),            # Extended outage  
        'long_outage': timedelta(days=7),           # Equipment failure
        'permanent_failure': timedelta(days=30),    # Stream dead
    }
    
    def classify_gap(self, gap_duration, stream_type):
        if stream_type == 'sporadic':  # GPS, app events
            # More tolerant of gaps
            thresholds = {k: v * 3 for k, v in self.GAP_TYPES.items()}
        else:
            thresholds = self.GAP_TYPES
            
        for gap_type, threshold in thresholds.items():
            if gap_duration <= threshold:
                return gap_type
        return 'permanent_failure'
```

### 3.2 Component-Specific Handling

| Component | Missing Data Support | Strategy |
|-----------|---------------------|----------|
| **Prophet** | ✅ Good | Native interpolation, gap-aware retraining |
| **River** | ✅✅ Excellent | Skip missing features, learn availability patterns |
| **Ensemble** | ✅✅ Excellent | Confidence weighting, graceful degradation |

### 3.3 Stream Health Tracking
```python
class StreamHealthTracker:
    def __init__(self):
        self.consecutive_missing = 0
        self.total_points = 0
        self.missing_points = 0
        self.last_retrain = None
        
        # Thresholds
        self.MAX_CONSECUTIVE_MISSING = 48  # 4 hours at 5-min intervals
        self.MIN_AVAILABILITY = 0.8        # 80% uptime required
        
    def can_prophet_predict(self):
        if self.consecutive_missing > self.MAX_CONSECUTIVE_MISSING:
            return False
        availability = 1 - (self.missing_points / max(self.total_points, 1))
        return availability >= self.MIN_AVAILABILITY
    
    def get_health_score(self):
        # 0-1 score combining availability and recency
        availability = 1 - (self.missing_points / max(self.total_points, 1))
        recency_penalty = min(self.consecutive_missing / self.MAX_CONSECUTIVE_MISSING, 1.0)
        return availability * (1 - recency_penalty)
```

---

## 4. Implementation Architecture

### 4.1 Main System Class
```python
class RobustAnomalySystem:
    def __init__(self):
        # Core components
        self.individual_analyzer = IndividualStreamAnalyzer()      # Tier 1: River models
        self.cross_stream_detector = CrossStreamDetector()        # Tier 2: River multivariate  
        self.ensemble = HealthAwareEnsemble()                     # Tier 3: Ensemble
        self.causal_explainer = CausalExplanationLayer()         # Tier 4: Causality
        
        # Stream definitions
        self.stream_definitions = {
            'speech_activity': {'type': 'sporadic', 'group': 'interaction'},
            'step_counter': {'type': 'continuous_smooth', 'group': 'motion'},
            'accelerometer_x': {'type': 'continuous_noisy', 'group': 'motion'},
            'heart_rate': {'type': 'continuous_smooth', 'group': 'biometric'},
            'gps_lat': {'type': 'sporadic', 'group': 'location'},
            'app_launcher': {'type': 'discrete_events', 'group': 'interaction'},
            # ... define all 30+ streams
        }
        
    def process_timestamp(self, timestamp, raw_data):
        # Tier 1: Individual stream analysis
        tier_1_scores = self.individual_analyzer.analyze_all_streams(timestamp, raw_data)
        
        # Tier 2: Cross-stream pattern detection
        tier_2_score = self.cross_stream_detector.detect(timestamp, raw_data)
        
        # Tier 3: Ensemble prediction
        tier_3_result = self.ensemble.predict(
            tier_1_scores, 
            tier_2_score, 
            self.individual_analyzer.stream_health
        )
        
        # Tier 4: Causal explanation (if needed)
        if self.causal_explainer.should_explain(tier_1_scores, tier_2_score, tier_3_result):
            explanation = self.causal_explainer.explain_anomaly(
                tier_3_result, raw_data, timestamp
            )
            tier_3_result['causal_explanation'] = explanation
        
        # Store results for learning
        self._store_results(timestamp, tier_1_scores, tier_2_score, tier_3_result)
        
        return tier_3_result
    
    def analyze_with_full_explanation(self, timestamp, raw_data):
        """Force causal explanation even for low anomalies (for debugging)"""
        result = self.process_timestamp(timestamp, raw_data)
        
        if 'causal_explanation' not in result:
            # Force explanation generation
            explanation = self.causal_explainer.explain_anomaly(
                result, raw_data, timestamp
            )
            result['causal_explanation'] = explanation
            
        return result
```

### 4.2 Streaming Data Pipeline
```python
class StreamingPipeline:
    def __init__(self):
        self.anomaly_system = RobustAnomalySystem()
        self.data_buffer = {}
        self.last_processing_time = {}
        
    async def process_stream(self, stream_name, timestamp, value):
        # Buffer incoming data
        if stream_name not in self.data_buffer:
            self.data_buffer[stream_name] = {}
        self.data_buffer[stream_name][timestamp] = value
        
        # Process when we have enough data or timeout
        if self._should_process(timestamp):
            await self._process_batch(timestamp)
    
    def _should_process(self, current_time):
        # Process every 5 minutes or when sufficient data accumulated
        last_process = self.last_processing_time.get('last', datetime.min)
        return (current_time - last_process) >= timedelta(minutes=5)
    
    async def _process_batch(self, timestamp):
        # Aggregate data for this timestamp
        raw_data = self._aggregate_buffer_data(timestamp)
        
        # Run anomaly detection
        result = self.anomaly_system.process_timestamp(timestamp, raw_data)
        
        # Store and alert if needed
        await self._handle_result(timestamp, result)
```

---

## 5. Database Schema

### 5.1 Core Tables
```sql
-- Raw time series data
CREATE TABLE time_series_data (
    timestamp TIMESTAMP NOT NULL,
    stream_id VARCHAR(50) NOT NULL,
    value FLOAT,
    is_missing BOOLEAN DEFAULT FALSE,
    missing_reason VARCHAR(100),
    PRIMARY KEY (timestamp, stream_id),
    INDEX idx_timestamp (timestamp),
    INDEX idx_stream_time (stream_id, timestamp)
);

-- Anomaly detection results
CREATE TABLE anomaly_scores (
    timestamp TIMESTAMP NOT NULL,
    stream_id VARCHAR(50),
    method ENUM('river_individual', 'river_multivariate', 'ensemble') NOT NULL,
    anomaly_score FLOAT,
    confidence FLOAT,
    metadata JSON,
    PRIMARY KEY (timestamp, stream_id, method),
    INDEX idx_high_scores (anomaly_score DESC, timestamp)
);

-- Causal explanation results
CREATE TABLE causal_explanations (
    timestamp TIMESTAMP NOT NULL,
    anomaly_id VARCHAR(100) NOT NULL,
    primary_cause VARCHAR(100),
    confidence FLOAT,
    causal_attribution JSON,        -- JSON: {"accelerometer": 0.6, "gps": 0.3}
    temporal_sequence JSON,         -- JSON: [{"time": "10:31", "event": "accel_increase"}]
    evidence JSON,                  -- JSON: {"sequence_match": "exercise_pattern"}
    alternative_explanations JSON,  -- JSON: [{"cause": "stress", "prob": 0.05}]
    PRIMARY KEY (timestamp, anomaly_id),
    INDEX idx_cause (primary_cause, timestamp),
    FOREIGN KEY (timestamp) REFERENCES anomaly_scores(timestamp)
);

-- Stream health tracking
CREATE TABLE stream_health (
    timestamp TIMESTAMP NOT NULL,
    stream_id VARCHAR(50) NOT NULL,
    availability_score FLOAT,
    consecutive_missing INT,
    needs_retraining BOOLEAN,
    last_retrain_time TIMESTAMP,
    PRIMARY KEY (timestamp, stream_id)
);

-- Gap pattern learning
CREATE TABLE gap_patterns (
    timestamp TIMESTAMP NOT NULL,
    context VARCHAR(50),  -- 'work_hours', 'sleep_hours', 'weekend'
    availability_vector JSON,  -- Which streams were available
    pattern_frequency FLOAT,
    is_anomalous BOOLEAN,
    INDEX idx_context_time (context, timestamp)
);
```

### 5.2 Performance Optimizations
- **Partitioning**: Partition by timestamp (monthly)
- **Retention**: Auto-delete raw data > 6 months, keep aggregated anomaly scores
- **Indexes**: Optimize for time-range and high-anomaly-score queries
- **Compression**: Use time-series compression for raw data storage

---

## 6. Performance & Scaling

### 6.1 Computational Requirements

| Component | CPU per Update | Memory | Frequency |
|-----------|---------------|---------|-----------|
| River Individual (30+ models) | ~30ms | 100MB | Real-time |
| River Multivariate | ~1-5ms | 50MB | Real-time |
| Ensemble | ~1ms | 10MB | Real-time |
| Causal Explanation | ~50ms | 50MB | On anomalies only |
| **Total per timestamp** | **~35ms** | **210MB** | **5-min intervals** |
| **With causal explanation** | **~85ms** | **260MB** | **When anomalous** |

### 6.2 Hardware Recommendations

**Development/Testing**:
- 1 vCPU, 1GB RAM
- Cost: ~$10/month
- Handles: 5-minute data, up to 30 streams

**Production**:
- 2 vCPU, 4GB RAM  
- Cost: ~$40/month
- Handles: Real-time streaming, 100+ streams with causal explanations

**High-Scale**:
- 4 vCPU, 8GB RAM
- Cost: ~$100/month  
- Handles: Sub-second processing, 500+ streams with full causality analysis

### 6.3 Optimization Strategies

**For High-Frequency Data**:
```python
# River scales naturally with data frequency
river_configs = {
    'high_frequency': {
        'max_features': 40,           # Limit feature space
        'explanation_threshold': 0.8,  # Only explain high anomalies
        'causal_analysis_interval': 60, # Batch causal analysis every minute
    }
}

# Async processing for causal explanations
async def process_with_explanation():
    # Fast path: Always run Tiers 1-3
    anomaly_result = await fast_anomaly_detection(data)
    
    # Slow path: Run causal explanation asynchronously if needed
    if anomaly_result['score'] > threshold:
        explanation_task = asyncio.create_task(
            causal_explainer.explain_anomaly(anomaly_result)
        )
        # Return immediate result, explanation follows later
        return anomaly_result, explanation_task
```

**Feature Dimensionality Management**:
```python
# Intelligent feature selection for River
class AdaptiveFeatureSelector:
    def select_features_for_river(self, all_features, max_features=40):
        # Always include gap indicators (core innovation)
        core_features = {
            k: v for k, v in all_features.items() 
            if k.endswith('_available') or k in ['hour', 'day_of_week']
        }
        
        # Add most predictive main stream values
        remaining_budget = max_features - len(core_features)
        important_streams = self.get_top_predictive_streams(remaining_budget)
        
        selected = {**core_features, **important_streams}
        return selected

# Causal explanation optimization
causal_configs = {
    'fast_mode': {
        'methods': ['sequence_matching'],        # Skip expensive Bayesian inference
        'temporal_window_minutes': 10,           # Shorter analysis window
        'max_alternative_explanations': 2        # Fewer alternatives
    },
    'thorough_mode': {
        'methods': ['bayesian', 'sequence', 'temporal'],  # All methods
        'temporal_window_minutes': 60,                     # Longer analysis
        'max_alternative_explanations': 5                  # More alternatives
    }
}
```

---

## 7. Deployment & Operations

### 7.1 Service Architecture
```yaml
# docker-compose.yml
version: '3.8'
services:
  anomaly-detector:
    image: anomaly-detector:latest
    environment:
      - DATABASE_URL=postgresql://user:pass@db:5432/anomaly_db
      - REDIS_URL=redis://cache:6379
    depends_on:
      - database
      - cache
      
  database:
    image: timescaledb/timescaledb:latest
    environment:
      - POSTGRES_DB=anomaly_db
    volumes:
      - timeseries_data:/var/lib/postgresql/data
      
  cache:
    image: redis:alpine
    
  monitoring:
    image: grafana/grafana:latest
    ports:
      - "3000:3000"
```

### 7.2 Monitoring & Alerts
```python
# Key metrics to monitor
MONITORING_METRICS = {
    'system_health': [
        'streams_available_count',
        'average_processing_latency',  
        'anomaly_detection_rate',
        'false_positive_rate'
    ],
    'stream_health': [
        'stream_availability_percentage',
        'consecutive_missing_duration',
        'prophet_model_accuracy'
    ],
    'performance': [
        'memory_usage',
        'cpu_utilization', 
        'database_query_time'
    ]
}

# Alert thresholds
ALERT_THRESHOLDS = {
    'high_anomaly_rate': 0.1,        # >10% anomalies in 1 hour
    'system_degradation': 0.7,       # <70% streams available
    'processing_latency': 10.0,      # >10 seconds per batch
}
```

### 7.3 Model Management
```python
class ModelManager:
    def __init__(self):
        self.model_versions = {}
        self.performance_tracker = PerformanceTracker()
        
    def should_retrain_prophet(self, stream_id):
        # Retrain if performance degraded or after major gaps
        performance = self.performance_tracker.get_accuracy(stream_id)
        gap_duration = self.stream_health[stream_id].consecutive_missing
        
        return (performance < 0.8 or gap_duration > 144)  # 12 hours
    
    def backup_models(self):
        # Periodic model checkpointing
        for stream_id, model in self.prophet_models.items():
            joblib.dump(model, f'models/prophet_{stream_id}_{timestamp}.pkl')
```

---

## 8. Implementation Phases

### Phase 1: Core River Infrastructure (Weeks 1-2)
- [ ] Database schema setup with causal explanation tables
- [ ] Basic streaming pipeline
- [ ] River integration for individual streams (Tier 1)
- [ ] Simple ensemble (weighted average) for Tier 3
- [ ] Health tracking and gap indicators

### Phase 2: Cross-Stream & Gap Learning (Weeks 3-4)  
- [ ] River multivariate detection with gap indicators (Tier 2)
- [ ] Stream health tracking and availability patterns
- [ ] Enhanced ensemble with confidence weighting
- [ ] Basic monitoring and alerting

### Phase 3: Causal Explanation Layer (Weeks 5-6)
- [ ] Bayesian causal network implementation
- [ ] Event sequence pattern matching
- [ ] Temporal correlation analysis
- [ ] Causal explanation synthesis and output formatting

### Phase 4: Production Hardening (Weeks 7-8)
- [ ] Performance optimization for all four tiers
- [ ] Advanced causal explanation features
- [ ] Model management and health monitoring
- [ ] Dashboard with causal insights visualization

---

## 9. Success Metrics

### 9.1 Technical Metrics
- **Latency**: <35ms per timestamp processing, <85ms with causal explanation
- **Availability**: 99.9% system uptime
- **Accuracy**: <5% false positive rate on known anomalies
- **Scalability**: Support 100+ streams without degradation
- **Explanation Quality**: 90% of causal explanations rated as helpful by domain experts
- **Cold Start**: Useful anomaly detection from first data point (no training period)

### 9.2 Business Metrics  
- **Coverage**: Detect anomalies even with 50% streams missing
- **Adaptability**: Adjust to new behavioral patterns within 1 hour
- **Reliability**: Continue operating with individual component failures
- **Interpretability**: Provide actionable causal explanations for 95% of high-confidence anomalies
- **Real-time Value**: Immediate anomaly detection without waiting for training data accumulation

---

## 10. Risk Mitigation

### 10.1 Technical Risks
| Risk | Impact | Mitigation |
|------|--------|------------|
| Prophet memory explosion | High | Rolling windows, model versioning |
| River performance degradation | Medium | Feature selection, hierarchical detection |
| Database bottlenecks | High | Time-series DB, partitioning, caching |
| Model drift | Medium | Continuous monitoring, auto-retraining |

### 10.2 Operational Risks
| Risk | Impact | Mitigation |
|------|--------|------------|
| All streams fail | High | Graceful degradation, backup detection |
| False positive flood | Medium | Confidence scoring, rate limiting |
| Model corruption | Medium | Model versioning, automatic rollback |

---

This specification provides a complete roadmap for implementing a production-ready multi-stream anomaly detection system with robust missing data handling, gap pattern learning, and causal explanation capabilities.

## Key Innovations

**Four-Tier Architecture**:
- **Tier 1**: River individual stream models for immediate learning
- **Tier 2**: River multivariate detection with gap pattern learning  
- **Tier 3**: Health-aware ensemble with confidence weighting
- **Tier 4**: Causal explanation layer for understanding anomaly root causes

**Technical Advantages**:
- ✅ **Immediate usefulness**: Works from first data point, no training period
- ✅ **Gap-aware learning**: Treats data availability as behavioral signals
- ✅ **Causal insights**: Explains WHY anomalies occur, not just THAT they occur
- ✅ **Unified technology**: Single River framework across all detection tiers
- ✅ **Operational simplicity**: No batch retraining, continuous learning
- ✅ **Resource efficiency**: 10x lower compute requirements than Prophet-based approaches

**Business Value**:
- 🚀 **Day 1 deployment**: Immediate anomaly detection without historical data requirements
- 🎯 **Actionable insights**: Causal explanations enable targeted interventions
- 💰 **Cost effective**: Lower infrastructure costs while providing superior capabilities
- 🔧 **Maintainable**: Simple architecture reduces operational complexity