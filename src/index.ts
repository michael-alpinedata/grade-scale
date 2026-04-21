import fastify from 'fastify';
import cors from '@fastify/cors';
import { 
  validatorCompiler, 
  serializerCompiler, 
  ZodTypeProvider 
} from 'fastify-type-provider-zod';
import { prisma } from './utils/prisma';
import { EvaluationService } from './services/evaluation.service';
import { CreateSubmissionSchema } from './schemas/submission.schema';
import { z } from 'zod';
import { AppError } from './errors/AppError';


export const server = fastify({
  logger: {
    transport: {
      target: 'pino-pretty',
      options: {
        colorize: true,
      },
    },
  },
}).withTypeProvider<ZodTypeProvider>();

server.setValidatorCompiler(validatorCompiler);
server.setSerializerCompiler(serializerCompiler);

const isVerbose = process.argv.includes('--verbose');
const evaluationService = new EvaluationService(undefined, server.log, isVerbose);

if (isVerbose) {
  server.log.info('🛠️ Verbose mode enabled');
}

// Standardized Error Handler
server.setErrorHandler((error, request, reply) => {
  if (error instanceof z.ZodError) {
    return reply.status(400).send({
      code: 'VALIDATION_ERROR',
      message: 'Données invalides',
      details: error.issues,
    });
  }

  if (error instanceof AppError) {
    return reply.status(error.statusCode).send({
      code: error.name.toUpperCase(),
      message: error.message,
    });
  }


  request.log.error(error);
  return reply.status(500).send({
    code: 'INTERNAL_SERVER_ERROR',
    message: 'Une erreur imprévue est survenue',
  });
});


// Healthcheck
server.get('/health', async () => ({ status: 'ok' }));

// Root
server.get('/', async () => ({ 
  name: "GradeScale API", 
  version: "1.0.0", 
  status: "Operational",
  documentation: "https://github.com/MichaelG-create/grade-scale"
}));

/**
 * Route POST /submissions
 * Ingestion d'une copie et lancement du service d'évaluation en tâche de fond (Async)
 */
server.post('/submissions', {
  schema: {
    body: CreateSubmissionSchema,
    response: {
      202: z.object({
        submissionId: z.uuid(),
        message: z.string(),
      }),
    },
  },
}, async (request, reply) => {
  const { studentPseudoId, questionId, content } = request.body;

  // 1. Enregistrement en base de données
  const submission = await prisma.submission.create({
    data: {
      studentPseudoId,
      questionId,
      content,
    },
  });

  // 2. Lancement asynchrone de la correction (Background Job)
  // On ne "await" pas pour rendre la main immédiatement au client
  evaluationService.evaluateSubmission(submission.id).catch((err) => {
    request.log.error(`[Background Task] Erreur lors de l'évaluation ${submission.id}:`, err);
  });

  return reply.status(202).send({
    submissionId: submission.id,
    message: "Copie reçue. Correction en cours...",
  });
});

/**
 * Route GET /evaluations/:submissionId
 * Récupération du résultat ou du statut de la correction
 */
server.get('/evaluations/:submissionId', {
  schema: {
    params: z.object({
      submissionId: z.uuid(),
    }),
  },
}, async (request, reply) => {
  const { submissionId } = request.params;

  const evaluation = await prisma.evaluation.findUnique({
    where: { submissionId },
    include: {
      submission: {
        include: {
          question: {
            include: {
              subject: true,
              rubrics: {
                include: { criteria: true }
              }
            }
          }
        }
      },
      criteriaEvaluations: {
        include: { criterion: true }
      }
    }
  });

  if (!evaluation) {
    return reply.status(404).send({ error: "Évaluation non trouvée pour cette soumission" });
  }

  return evaluation;
});

/**
 * Route GET /questions
 * Liste des exercices pour le frontend
 */
server.get('/questions', async () => {
  return await prisma.question.findMany({
    include: { subject: true }
  });
});

// Lancement du serveur (uniquement si le fichier est exécuté directement)
if (require.main === module || !process.env.VITEST) {
  const start = async () => {
    try {
      server.register(cors, { 
        origin: '*', 
        methods: ['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS'],
        allowedHeaders: ['Content-Type', 'Authorization']
      });
      
      const port = Number(process.env.PORT) || 3000;
      await server.listen({ port, host: '0.0.0.0' });
      
      console.log(`🚀 GradeScale Server ready at http://localhost:${port}`);
    } catch (err) {
      server.log.error(err);
      process.exit(1);
    }
  };

  start();
}
